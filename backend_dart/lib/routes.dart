import 'dart:convert';

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

    // Always scrape/cache in original language
    var items = menuCache.readOriginal(url);

    if (items == null) {
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

      final rawItems = jsonDecode(scraperResponse.body) as List<dynamic>;
      items = rawItems
          .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
          .toList();
      menuCache.writeOriginal(url, items);
    }

    // Translate if requested
    if (language != null && language.isNotEmpty) {
      final cached = menuCache.readTranslated(url, language);
      if (cached != null) {
        items = cached;
      } else {
        try {
          items = await translationService.translate(
            language: language,
            items: items,
          );
          menuCache.writeTranslated(url, language, items);
        } catch (e, st) {
          print('Translation error: $e\n$st');
          return Response.internalServerError(
            body: jsonEncode({'error': 'Translation failed: $e'}),
            headers: {'Content-Type': 'application/json'},
          );
        }
      }
    }

    final base = items
        .firstWhere(
          (i) => i.currency.isNotEmpty,
          orElse: () => const MenuItem(name: '', currency: 'USD'),
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
      items: items,
      exchangeRates: filteredExchangeRates,
    );

    return Response.ok(
      jsonEncode(scrapeResponse.toJson()),
      headers: {'Content-Type': 'application/json'},
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
