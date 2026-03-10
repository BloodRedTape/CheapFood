import 'dart:convert';

import 'package:common_dart/common_dart.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'menu_cache.dart';
import 'user_service.dart';

Response _unauthorized([String message = 'Unauthorized']) =>
    Response(401, body: jsonEncode({'error': message}), headers: {'Content-Type': 'application/json'});

String? _extractLogin(Request request, UserService userService) {
  final header = request.headers['authorization'] ?? '';
  if (!header.startsWith('Bearer ')) return null;
  return userService.verifyToken(header.substring(7));
}

List<RestaurantPreviewInfo> buildRestaurantPreviews(List<String> urls, MenuCache menuCache) {
  return urls.map((url) {
    final info = menuCache.readRestaurantInfo(url);
    final categories = menuCache.readOriginal(url) ?? [];
    final totalItems = categories.fold(0, (sum, c) => sum + c.items.length);
    final itemsWithPrice = categories.fold(
      0,
      (sum, c) => sum + c.items.where((item) => item.variations.any((v) => v.price != null)).length,
    );
    return RestaurantPreviewInfo(
      url: url,
      name: info?.name,
      totalItems: totalItems,
      itemsWithPrice: itemsWithPrice,
      iconUrl: info?.iconUrl,
    );
  }).toList();
}

Router buildRestaurantRouter({required UserService userService, required MenuCache menuCache}) {
  final router = Router();

  router.get('/', (Request request) async {
    final login = _extractLogin(request, userService);
    if (login == null) return _unauthorized();
    final user = userService.getUser(login);
    if (user == null) return _unauthorized('User not found');
    final previews = buildRestaurantPreviews(user.urls, menuCache);
    return Response.ok(
      jsonEncode({'restaurants': previews.map((p) => p.toJson()).toList()}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.post('/', (Request request) async {
    final login = _extractLogin(request, userService);
    if (login == null) return _unauthorized();
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'url required'}), headers: {'Content-Type': 'application/json'});
    }
    final user = userService.addUrl(login, url);
    if (user == null) return _unauthorized('User not found');
    final previews = buildRestaurantPreviews(user.urls, menuCache);
    return Response.ok(
      jsonEncode({'restaurants': previews.map((p) => p.toJson()).toList()}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.delete('/', (Request request) async {
    final login = _extractLogin(request, userService);
    if (login == null) return _unauthorized();
    final body = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final url = body['url'] as String?;
    if (url == null || url.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'url required'}), headers: {'Content-Type': 'application/json'});
    }
    final user = userService.removeUrl(login, url);
    if (user == null) return _unauthorized('User not found');
    final previews = buildRestaurantPreviews(user.urls, menuCache);
    return Response.ok(
      jsonEncode({'restaurants': previews.map((p) => p.toJson()).toList()}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  return router;
}
