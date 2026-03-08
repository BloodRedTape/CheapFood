import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'user_service.dart';

Response _unauthorized([String message = 'Unauthorized']) =>
    Response(401, body: jsonEncode({'error': message}), headers: {'Content-Type': 'application/json'});

String? _extractLogin(Request request, UserService userService) {
  final header = request.headers['authorization'] ?? '';
  if (!header.startsWith('Bearer ')) return null;
  return userService.verifyToken(header.substring(7));
}

Router buildRestaurantRouter({required UserService userService}) {
  final router = Router();

  router.get('/', (Request request) async {
    final login = _extractLogin(request, userService);
    if (login == null) return _unauthorized();
    final user = userService.getUser(login);
    if (user == null) return _unauthorized('User not found');
    return Response.ok(jsonEncode({'urls': user.urls}), headers: {'Content-Type': 'application/json'});
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
    return Response.ok(jsonEncode({'urls': user.urls}), headers: {'Content-Type': 'application/json'});
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
    return Response.ok(jsonEncode({'urls': user.urls}), headers: {'Content-Type': 'application/json'});
  });

  return router;
}
