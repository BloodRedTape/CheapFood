import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

const String _scraperUrl = 'http://localhost:8000';
const int _port = 8080;

Middleware get _corsMiddleware => (Handler handler) {
      return (Request request) async {
        if (request.method == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders);
        }
        final response = await handler(request);
        return response.change(headers: _corsHeaders);
      };
    };

const Map<String, String> _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

void main() async {
  final router = Router();

  router.post('/scrape', (Request request) async {
    final body = await request.readAsString();
    final scraperResponse = await http.post(
      Uri.parse('$_scraperUrl/scrape'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );
    return Response(
      scraperResponse.statusCode,
      body: scraperResponse.body,
      headers: {'Content-Type': 'application/json'},
    );
  });

  router.get('/health', (Request request) async {
    return Response.ok(
      jsonEncode({'status': 'ok'}),
      headers: {'Content-Type': 'application/json'},
    );
  });

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware)
      .addHandler(router.call);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);
  print('Backend running on http://localhost:${server.port}');
}
