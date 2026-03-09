import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_rate_limiter/shelf_rate_limiter.dart';
import 'package:shelf_router/shelf_router.dart';

import 'config.dart';
import 'menu_cache.dart';
import 'restaurant_routes.dart';
import 'user_service.dart';

Router buildAuthRouter({required UserService userService, required MenuCache menuCache}) {
  final router = Router();

  final rateLimiter = ShelfRateLimiter(
    storage: MemStorage(),
    duration: const Duration(minutes: 1),
    maxRequests: 10,
  );

  final inner = Router();

  inner.post('/register', (Request request) async {
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
    final previews = buildRestaurantPreviews(user.urls, menuCache);
    return Response.ok(jsonEncode({'token': token, 'login': user.login, 'restaurants': previews.map((p) => p.toJson()).toList()}), headers: {'Content-Type': 'application/json'});
  });

  inner.post('/login', (Request request) async {
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
    final previews = buildRestaurantPreviews(user.urls, menuCache);
    return Response.ok(jsonEncode({'token': token, 'login': user.login, 'restaurants': previews.map((p) => p.toJson()).toList()}), headers: {'Content-Type': 'application/json'});
  });

  router.mount('/', Pipeline().addMiddleware(rateLimiter.rateLimiter()).addHandler(inner.call));

  return router;
}
