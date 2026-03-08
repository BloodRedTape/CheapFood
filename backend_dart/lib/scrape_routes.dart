import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:common_dart/common_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config.dart';
import 'exchange_rate_cache.dart';
import 'menu_cache.dart';
import 'rate_limiter.dart';
import 'scrape_deduplicator.dart';
import 'translation_service.dart';
import 'user_service.dart';

String? _extractLogin(Request request, UserService userService) {
  final header = request.headers['authorization'] ?? '';
  if (!header.startsWith('Bearer ')) return null;
  return userService.verifyToken(header.substring(7));
}

Router buildScrapeRouter({
  required MenuCache menuCache,
  required ExchangeRateCache rateCache,
  required TranslationService translationService,
  required UserService userService,
}) {
  final router = Router();

  // 5 scrape requests per minute per user
  final rateLimiter = RateLimiter(maxRequests: 5, window: const Duration(minutes: 1));

  final deduplicator = ScrapeDeduplicator();

  // NOTE: All routes in this router require a valid JWT Bearer token.
  // Any new route added here MUST start with _extractLogin() check before processing.

  router.post('/stream', (Request request) async {
    final login = _extractLogin(request, userService);
    if (login == null) {
      return Response(
        401,
        body: 'event: error\ndata: Unauthorized\n\n',
        headers: {'Content-Type': 'text/event-stream'},
      );
    }

    if (!rateLimiter.allow(login)) {
      return Response(
        429,
        body: 'event: error\ndata: Too many requests\n\n',
        headers: {'Content-Type': 'text/event-stream'},
      );
    }

    final body = await request.readAsString();
    final requestJson = jsonDecode(body) as Map<String, dynamic>;
    final url = requestJson['url'] as String;
    final language = requestJson['language'] as String?;
    final forceRefresh = requestJson['force_refresh'] as bool? ?? false;

    if (forceRefresh) menuCache.clearUrl(url);

    // Build the per-request output controller (single-subscriber, feeds the HTTP response).
    final outputController = StreamController<List<int>>();

    // Helper: sends categories through translation + exchange rates, then closes outputController.
    Future<void> finishWithCategories(List<MenuCategory> categories) async {
      if (language != null && language.isNotEmpty) {
        final cached = menuCache.readTranslated(url, language);
        if (cached != null) {
          categories = cached;
        } else {
          try {
            outputController.add(utf8.encode('event: progress\ndata: Translating menu to $language...\n\n'));
            categories = await translationService.translate(language: language, categories: categories);
            menuCache.writeTranslated(url, language, categories);
          } catch (e) {
            print('Translation error: $e');
            outputController.add(utf8.encode('event: error\ndata: Translation failed\n\n'));
            await outputController.close();
            return;
          }
        }
      }

      final base =
          categories
              .expand((c) => c.items)
              .expand((i) => i.variations)
              .firstWhere((v) => v.currency.isNotEmpty, orElse: () => const MenuItemVariation(currency: 'USD'))
              .currency;

      outputController.add(utf8.encode('event: progress\ndata: Fetching exchange rates for $base...\n\n'));
      try {
        final raw = await rateCache.getRates(base);
        final filteredRates = Map.fromEntries(raw.rates.entries.where((e) => allowedCurrencies.contains(e.key)));
        final exchangeRates = ExchangeRates(base: raw.base, rates: filteredRates);
        final payload = jsonEncode(ScrapeResponse(categories: categories, exchangeRates: exchangeRates).toJson());
        outputController.add(utf8.encode('event: result\ndata: $payload\n\n'));
      } catch (e) {
        print('Exchange rates error: $e');
        outputController.add(utf8.encode('event: error\ndata: Exchange rates failed\n\n'));
      }
      await outputController.close();
    }

    // --- Cache hit: serve immediately without touching the deduplicator ---
    final translatedCached = language != null && language.isNotEmpty ? menuCache.readTranslated(url, language) : null;
    if (translatedCached != null) {
      finishWithCategories(translatedCached).catchError((Object e) {
        print('Finish error (translated cache): $e');
        if (!outputController.isClosed) {
          outputController.add(utf8.encode('event: error\ndata: Scrape failed\n\n'));
          outputController.close();
        }
      });
      return _sseResponse(outputController.stream);
    }

    final originalCached = menuCache.readOriginal(url);
    if (originalCached != null) {
      finishWithCategories(originalCached).catchError((Object e) {
        print('Finish error (original cache): $e');
        if (!outputController.isClosed) {
          outputController.add(utf8.encode('event: error\ndata: Scrape failed\n\n'));
          outputController.close();
        }
      });
      return _sseResponse(outputController.stream);
    }

    // --- Deduplication: join existing in-flight scrape or start a new one ---
    final existingStream = deduplicator.subscribe(url);
    if (existingStream != null) {
      // Another request is already scraping this URL.
      // Replay broadcast events into our per-request output controller.
      print('Scrape dedup: joining in-flight scrape for $url');
      existingStream.listen(
        (chunk) {
          if (!outputController.isClosed) outputController.add(chunk);
        },
        onError: (Object e) {
          print('Scrape dedup stream error: $e');
          if (!outputController.isClosed) {
            outputController.add(utf8.encode('event: error\ndata: Scrape failed\n\n'));
            outputController.close();
          }
        },
        onDone: () {
          // The broadcast stream closed — the primary scrape finished (result or error
          // was already forwarded event-by-event). Close our output too.
          if (!outputController.isClosed) outputController.close();
        },
      );
      return _sseResponse(outputController.stream);
    }

    // Primary request: register with deduplicator and run the scrape.
    final broadcastController = deduplicator.register(url);

    Future<void> runScrape() async {
      // Also pipe broadcast events into this request's own output.
      broadcastController.stream.listen(
        (chunk) {
          if (!outputController.isClosed) outputController.add(chunk);
        },
        onDone: () {
          if (!outputController.isClosed) outputController.close();
        },
        onError: (Object e) {
          if (!outputController.isClosed) {
            outputController.add(utf8.encode('event: error\ndata: Scrape failed\n\n'));
            outputController.close();
          }
        },
      );

      try {
        final uri = Uri.parse('$scraperUrl/scrape/stream');
        final ioClient = HttpClient()..autoUncompress = false;
        final ioRequest = await ioClient.postUrl(uri);
        ioRequest.headers.set('Content-Type', 'application/json');
        ioRequest.write(body);
        final ioResponse = await ioRequest.close();

        String buffer = '';
        String? eventType;
        String? eventData;

        await for (final chunk in ioResponse) {
          if (broadcastController.isClosed) break;

          buffer += utf8.decode(chunk);
          final lines = buffer.split('\n');
          buffer = lines.last;

          for (final line in lines.sublist(0, lines.length - 1)) {
            if (line.startsWith('event: ')) {
              eventType = line.substring(7).trim();
            } else if (line.startsWith('data: ')) {
              eventData = line.substring(6).trim();
            } else if (line.isEmpty && eventType != null && eventData != null) {
              if (eventType == 'progress') {
                broadcastController.add(utf8.encode('event: progress\ndata: $eventData\n\n'));
              } else if (eventType == 'error') {
                broadcastController.add(utf8.encode('event: error\ndata: $eventData\n\n'));
                await broadcastController.close();
                deduplicator.complete(url);
                ioClient.close();
                return;
              } else if (eventType == 'result') {
                final rawCategories = jsonDecode(eventData) as List<dynamic>;
                final categories = rawCategories.map((e) => MenuCategory.fromJson(e as Map<String, dynamic>)).toList();
                menuCache.writeOriginal(url, categories);
                ioClient.close();

                // Close broadcast — subscribers get onDone and will handle
                // their own translation/exchange-rate flow independently.
                await broadcastController.close();
                deduplicator.complete(url);

                // Primary request continues with full post-processing.
                await finishWithCategories(categories);
                return;
              }
              eventType = null;
              eventData = null;
            }
          }
        }

        await broadcastController.close();
        deduplicator.complete(url);
        ioClient.close();
      } catch (e) {
        print('Scrape forward error: $e');
        if (!broadcastController.isClosed) {
          broadcastController.add(utf8.encode('event: error\ndata: Scrape failed\n\n'));
          await broadcastController.close();
          deduplicator.complete(url);
        }
      }
    }

    runScrape().catchError((Object e) {
      print('runScrape uncaught error: $e');
      if (!broadcastController.isClosed) {
        broadcastController.add(utf8.encode('event: error\ndata: Scrape failed\n\n'));
        broadcastController.close();
        deduplicator.complete(url);
      }
      if (!outputController.isClosed) {
        outputController.add(utf8.encode('event: error\ndata: Scrape failed\n\n'));
        outputController.close();
      }
    });

    return _sseResponse(outputController.stream);
  });

  return router;
}

Response _sseResponse(Stream<List<int>> stream) => Response.ok(
      stream,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'X-Accel-Buffering': 'no',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
      },
      context: {'shelf.io.buffer_output': false},
    );
