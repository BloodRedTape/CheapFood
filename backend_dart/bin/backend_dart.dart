import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:backend_dart/config.dart';
import 'package:backend_dart/cors_middleware.dart';
import 'package:backend_dart/exchange_rate_cache.dart';
import 'package:backend_dart/menu_cache.dart';
import 'package:backend_dart/routes.dart';
import 'package:backend_dart/translation_service.dart';

void main() async {
  loadDotEnv();
  final rateCache = ExchangeRateCache();
  final menuCache = MenuCache();
  final translationService = TranslationService();

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsMiddleware)
      .addHandler(buildRouter(
        menuCache: menuCache,
        rateCache: rateCache,
        translationService: translationService,
      ).call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('Backend running on http://localhost:${server.port}');
}
