import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import 'package:backend_dart/config.dart';
import 'package:backend_dart/cors_middleware.dart';
import 'package:backend_dart/exchange_rate_cache.dart';
import 'package:backend_dart/menu_cache.dart';
import 'package:backend_dart/routes.dart';

void main() async {
  final rateCache = ExchangeRateCache();
  final menuCache = MenuCache();

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsMiddleware)
      .addHandler(buildRouter(menuCache: menuCache, rateCache: rateCache).call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  print('Backend running on http://localhost:${server.port}');
}
