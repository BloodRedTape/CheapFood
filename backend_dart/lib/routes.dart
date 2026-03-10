import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth_routes.dart';
import 'exchange_rate_cache.dart';
import 'menu_cache.dart';
import 'restaurant_routes.dart';
import 'scrape_routes.dart';
import 'translation_service.dart';
import 'user_service.dart';

Router buildRouter({
  required MenuCache menuCache,
  required ExchangeRateCache rateCache,
  required TranslationService translationService,
  required UserService userService,
}) {
  final router = Router();

  router.mount('/auth', buildAuthRouter(userService: userService, menuCache: menuCache).call);
  router.mount('/restaurants', buildRestaurantRouter(userService: userService, menuCache: menuCache).call);
  router.mount('/scrape', buildScrapeRouter(
    menuCache: menuCache,
    rateCache: rateCache,
    translationService: translationService,
    userService: userService,
  ).call);

  router.get('/health', (Request _) async {
    return Response.ok('{"status":"ok"}', headers: {'Content-Type': 'application/json'});
  });

  router.get('/favicon', (Request request) async {
    final domain = request.url.queryParameters['domain'];
    if (domain == null || domain.isEmpty) {
      return Response(400, body: 'domain required');
    }
    final uri = Uri.parse('https://www.google.com/s2/favicons?domain=${Uri.encodeComponent(domain)}&sz=32');
    try {
      final client = HttpClient();
      final req = await client.getUrl(uri);
      final res = await req.close();
      final bytes = await res.fold<List<int>>([], (buf, chunk) => buf..addAll(chunk));
      client.close();
      return Response.ok(bytes, headers: {
        'Content-Type': res.headers.contentType?.toString() ?? 'image/png',
        'Cache-Control': 'public, max-age=86400',
      });
    } catch (_) {
      return Response(502, body: 'Failed to fetch favicon');
    }
  });

  return router;
}
