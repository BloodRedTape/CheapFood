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

  return router;
}
