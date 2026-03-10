import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

import 'package:backend_dart/config.dart';
import 'package:backend_dart/cors_middleware.dart';
import 'package:backend_dart/exchange_rate_cache.dart';
import 'package:backend_dart/menu_cache.dart';
import 'package:backend_dart/routes.dart';
import 'package:backend_dart/translation_service.dart';
import 'package:backend_dart/user_service.dart';

void main() async {
  loadDotEnv();
  final rateCache = ExchangeRateCache();
  final menuCache = MenuCache();
  final translationService = TranslationService();
  final userService = UserService();

  final apiHandler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsMiddleware)
      .addHandler(buildRouter(
        menuCache: menuCache,
        rateCache: rateCache,
        translationService: translationService,
        userService: userService,
      ).call);

  final fp = frontendPath;
  final Handler handler;
  if (fp != null) {
    final staticHandler = createStaticHandler(fp, defaultDocument: 'index.html');
    // SPA fallback: API routes first, then static files, then index.html
    handler = (Request request) async {
      if (request.url.path.startsWith('api/') ||
          request.url.path.startsWith('auth/') ||
          request.url.path.startsWith('restaurants') ||
          request.url.path.startsWith('scrape/') ||
          request.url.path == 'health' ||
          request.url.path == 'favicon') {
        return apiHandler(request);
      }
      final staticResponse = await staticHandler(request);
      if (staticResponse.statusCode == 404) {
        // SPA fallback — serve index.html
        return staticHandler(request.change(path: ''));
      }
      return staticResponse;
    };
    print('Serving frontend from $fp');
  } else {
    handler = apiHandler;
  }

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port, shared: false);
  server.autoCompress = false;
  print('Backend running on http://localhost:${server.port}');
}
