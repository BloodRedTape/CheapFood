import 'dart:convert' show jsonDecode;

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'package:common_dart/common_dart.dart';

import 'exchange_rate_cache.dart';
import 'menu_cache.dart';
import 'rate_limiter.dart';
import 'scraper_service.dart';
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
  final rateLimiter = RateLimiter(maxRequests: 10, window: const Duration(minutes: 1));

  final scraperService = ScraperService(menuCache: menuCache, rateCache: rateCache, translationService: translationService);

  // NOTE: All routes in this router require a valid JWT Bearer token.
  // Any new route added here MUST start with _extractLogin() check before processing.

  router.post('/stream', (Request request) async {
    final login = _extractLogin(request, userService);
    if (login == null) {
      return Response(401, body: ScraperErrorEvent('Unauthorized').toSse(), headers: {'Content-Type': 'text/event-stream'});
    }

    if (!rateLimiter.allow(login)) {
      return Response(429, body: ScraperErrorEvent('Too many requests').toSse(), headers: {'Content-Type': 'text/event-stream'});
    }

    final body = await request.readAsString();
    final requestJson = jsonDecode(body) as Map<String, dynamic>;
    final url = requestJson['url'] as String;
    final language = requestJson['language'] as String?;
    final forceRefresh = requestJson['force_refresh'] as bool? ?? false;

    final stream = scraperService.scrape(url: url, requestBody: body, language: language, forceRefresh: forceRefresh);

    return _sseResponse(stream);
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
