import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:common_dart/common_dart.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf_rate_limiter/shelf_rate_limiter.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config.dart';
import 'exchange_rate_cache.dart';
import 'menu_cache.dart';
import 'rate_limiter.dart';
import 'translation_service.dart';
import 'user_service.dart';

Response _unauthorized([String message = 'Unauthorized']) =>
    Response(401, body: jsonEncode({'error': message}), headers: {'Content-Type': 'application/json'});

/// Extracts and verifies Bearer token, returns login or null.
String? _extractLogin(Request request, UserService userService) {
  final header = request.headers['authorization'] ?? '';
  if (!header.startsWith('Bearer ')) return null;
  return userService.verifyToken(header.substring(7));
}

Router buildRouter({
  required MenuCache menuCache,
  required ExchangeRateCache rateCache,
  required TranslationService translationService,
  required UserService userService,
}) {
  final router = Router();

  final authRateLimiter = ShelfRateLimiter(
    storage: MemStorage(),
    duration: const Duration(minutes: 1),
    maxRequests: 10,
  );

  // 5 scrape requests per minute per user
  final scrapeRateLimiter = RateLimiter(maxRequests: 5, window: const Duration(minutes: 1));

  // NOTE: All routes in this router require a valid JWT Bearer token.
  // Any new route added here MUST start with _extractLogin() check before processing.

  router.post('/scrape/stream', (Request request) async {
    final login = _extractLogin(request, userService);
    if (login == null) {
      return Response(
        401,
        body: 'event: error\ndata: Unauthorized\n\n',
        headers: {'Content-Type': 'text/event-stream'},
      );
    }

    if (!scrapeRateLimiter.allow(login)) {
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

    final controller = StreamController<List<int>>();

    // Shared: translate + exchange rates + emit result, then close controller
    Future<void> finishWithCategories(List<MenuCategory> categories) async {
      if (language != null && language.isNotEmpty) {
        final cached = menuCache.readTranslated(url, language);
        if (cached != null) {
          categories = cached;
        } else {
          try {
            controller.add(utf8.encode('event: progress\ndata: Translating menu to $language...\n\n'));
            categories = await translationService.translate(language: language, categories: categories);
            menuCache.writeTranslated(url, language, categories);
          } catch (e) {
            print('Translation error: $e');
            controller.add(utf8.encode('event: error\ndata: Translation failed\n\n'));
            await controller.close();
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

      controller.add(utf8.encode('event: progress\ndata: Fetching exchange rates for $base...\n\n'));
      try {
        final raw = await rateCache.getRates(base);
        final filteredRates = Map.fromEntries(raw.rates.entries.where((e) => allowedCurrencies.contains(e.key)));
        final exchangeRates = ExchangeRates(base: raw.base, rates: filteredRates);
        final payload = jsonEncode(ScrapeResponse(categories: categories, exchangeRates: exchangeRates).toJson());
        controller.add(utf8.encode('event: result\ndata: $payload\n\n'));
      } catch (e) {
        print('Exchange rates error: $e');
        controller.add(utf8.encode('event: error\ndata: Exchange rates failed\n\n'));
      }
      await controller.close();
    }

    Future<void> forward() async {
      // Check cache first — skip scraper if already cached
      final translatedCached = language != null && language.isNotEmpty ? menuCache.readTranslated(url, language) : null;

      if (translatedCached != null) {
        await finishWithCategories(translatedCached);
        return;
      }

      final originalCached = menuCache.readOriginal(url);
      if (originalCached != null) {
        await finishWithCategories(originalCached);
        return;
      }

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
        if (controller.isClosed) break;

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
              controller.add(utf8.encode('event: progress\ndata: $eventData\n\n'));
            } else if (eventType == 'error') {
              controller.add(utf8.encode('event: error\ndata: $eventData\n\n'));
              await controller.close();
              ioClient.close();
              return;
            } else if (eventType == 'result') {
              final rawCategories = jsonDecode(eventData) as List<dynamic>;
              final categories = rawCategories.map((e) => MenuCategory.fromJson(e as Map<String, dynamic>)).toList();
              menuCache.writeOriginal(url, categories);
              ioClient.close();
              await finishWithCategories(categories);
              return;
            }
            eventType = null;
            eventData = null;
          }
        }
      }

      await controller.close();
      ioClient.close();
    }

    forward().catchError((Object e) {
      print('Scrape forward error: $e');
      if (!controller.isClosed) {
        controller.add(utf8.encode('event: error\ndata: Scrape failed\n\n'));
        controller.close();
      }
    });

    return Response.ok(
      controller.stream,
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
  });

  // Auth routes — with rate limiting
  final authRouter = Router();

  authRouter.post('/register', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final login = body['login'] as String?;
    final password = body['password'] as String?;
    if (login == null || login.isEmpty || password == null || password.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'login and password required'}), headers: {'Content-Type': 'application/json'});
    }
    final allowed = allowedUsername;
    if (allowed != null && login != allowed) {
      return Response(403, body: jsonEncode({'error': 'registration not allowed'}), headers: {'Content-Type': 'application/json'});
    }
    final user = userService.register(login, password);
    if (user == null) {
      return Response(409, body: jsonEncode({'error': 'login already taken'}), headers: {'Content-Type': 'application/json'});
    }
    final token = userService.issueToken(user.login);
    return Response.ok(jsonEncode({'token': token, 'login': user.login, 'urls': user.urls}), headers: {'Content-Type': 'application/json'});
  });

  authRouter.post('/login', (Request request) async {
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final login = body['login'] as String?;
    final password = body['password'] as String?;
    if (login == null || password == null) {
      return Response(400, body: jsonEncode({'error': 'login and password required'}), headers: {'Content-Type': 'application/json'});
    }
    final allowed = allowedUsername;
    if (allowed != null && login != allowed) {
      return Response(401, body: jsonEncode({'error': 'invalid credentials'}), headers: {'Content-Type': 'application/json'});
    }
    final user = userService.authenticate(login, password);
    if (user == null) {
      return Response(401, body: jsonEncode({'error': 'invalid credentials'}), headers: {'Content-Type': 'application/json'});
    }
    final token = userService.issueToken(user.login);
    return Response.ok(jsonEncode({'token': token, 'login': user.login, 'urls': user.urls}), headers: {'Content-Type': 'application/json'});
  });

  final authHandler = Pipeline()
      .addMiddleware(authRateLimiter.rateLimiter())
      .addHandler(authRouter.call);

  router.mount('/auth', authHandler);

  // Restaurant routes — JWT protected
  router.get('/restaurants', (Request request) async {
    final login = _extractLogin(request, userService);
    if (login == null) return _unauthorized();
    final user = userService.getUser(login);
    if (user == null) return _unauthorized('User not found');
    return Response.ok(jsonEncode({'urls': user.urls}), headers: {'Content-Type': 'application/json'});
  });

  router.post('/restaurants', (Request request) async {
    final login = _extractLogin(request, userService);
    if (login == null) return _unauthorized();
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'url required'}), headers: {'Content-Type': 'application/json'});
    }
    final user = userService.addUrl(login, url);
    if (user == null) return _unauthorized('User not found');
    return Response.ok(jsonEncode({'urls': user.urls}), headers: {'Content-Type': 'application/json'});
  });

  router.delete('/restaurants', (Request request) async {
    final login = _extractLogin(request, userService);
    if (login == null) return _unauthorized();
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'url required'}), headers: {'Content-Type': 'application/json'});
    }
    final user = userService.removeUrl(login, url);
    if (user == null) return _unauthorized('User not found');
    return Response.ok(jsonEncode({'urls': user.urls}), headers: {'Content-Type': 'application/json'});
  });

  router.get('/health', (Request _) async {
    return Response.ok(jsonEncode({'status': 'ok'}), headers: {'Content-Type': 'application/json'});
  });

  return router;
}
