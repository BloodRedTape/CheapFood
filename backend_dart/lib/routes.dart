import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:common_dart/common_dart.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config.dart';
import 'exchange_rate_cache.dart';
import 'menu_cache.dart';
import 'translation_service.dart';

Router buildRouter({
  required MenuCache menuCache,
  required ExchangeRateCache rateCache,
  required TranslationService translationService,
}) {
  final router = Router();

  router.post('/scrape', (Request request) async {
    final body = await request.readAsString();
    final requestJson = jsonDecode(body) as Map<String, dynamic>;
    final url = requestJson['url'] as String;
    final language = requestJson['language'] as String?;
    final forceRefresh = requestJson['force_refresh'] as bool? ?? false;

    if (forceRefresh) menuCache.clearUrl(url);

    // Always scrape/cache in original language
    var categories = menuCache.readOriginal(url);

    if (categories == null) {
      final scraperResponse = await http.post(
        Uri.parse('$scraperUrl/scrape'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (scraperResponse.statusCode != 200) {
        return Response(
          scraperResponse.statusCode,
          body: scraperResponse.body,
          headers: {'Content-Type': 'application/json'},
        );
      }

      final rawCategories = jsonDecode(scraperResponse.body) as List<dynamic>;
      categories = rawCategories
          .map((e) => MenuCategory.fromJson(e as Map<String, dynamic>))
          .toList();
      menuCache.writeOriginal(url, categories);
    }

    // Translate if requested
    if (language != null && language.isNotEmpty) {
      final cached = menuCache.readTranslated(url, language);
      if (cached != null) {
        categories = cached;
      } else {
        try {
          categories = await translationService.translate(
            language: language,
            categories: categories,
          );
          menuCache.writeTranslated(url, language, categories);
        } catch (e, st) {
          print('Translation error: $e\n$st');
          return Response.internalServerError(
            body: jsonEncode({'error': 'Translation failed: $e'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }
    }

    final allVariations = categories.expand((c) => c.items).expand((i) => i.variations).toList();
    final base = allVariations
        .firstWhere(
          (v) => v.currency.isNotEmpty,
          orElse: () => const MenuItemVariation(currency: 'USD'),
        )
        .currency;

    final ExchangeRates exchangeRates;
    try {
      exchangeRates = await rateCache.getRates(base);
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final filteredRates = Map.fromEntries(
      exchangeRates.rates.entries
          .where((e) => allowedCurrencies.contains(e.key)),
    );
    final filteredExchangeRates = ExchangeRates(
      base: exchangeRates.base,
      rates: filteredRates,
    );

    final scrapeResponse = ScrapeResponse(
      categories: categories,
      exchangeRates: filteredExchangeRates,
    );

    return Response.ok(
      jsonEncode(scrapeResponse.toJson()),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.post('/scrape/stream', (Request request) async {
    final body = await request.readAsString();

    final controller = StreamController<List<int>>();

    Future<void> forward() async {
      final uri = Uri.parse('$scraperUrl/scrape/stream');
      final ioClient = HttpClient()..autoUncompress = false;
      final ioRequest = await ioClient.postUrl(uri);
      ioRequest.headers.set('Content-Type', 'application/json');
      ioRequest.write(body);
      final ioResponse = await ioRequest.close();

      await for (final chunk in ioResponse) {
        if (controller.isClosed) break;
        controller.add(chunk);
      }
      await controller.close();
      ioClient.close();
    }

    forward().catchError((Object e) {
      if (!controller.isClosed) {
        controller.add(utf8.encode('event: error\ndata: $e\n\n'));
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

  router.get('/health', (Request _) async {
    return Response.ok(
      jsonEncode({'status': 'ok'}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  return router;
}
