import 'dart:convert';
import 'dart:io';

import 'package:common_dart/common_dart.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

const String _scraperUrl = 'http://localhost:8000';
const int _port = 8080;
const String _exchangeRateApiUrl = 'https://api.exchangerate-api.com/v4/latest';
const Duration _cacheTtl = Duration(hours: 1);
const String _menuCacheDir = '.run_tree';
const Set<String> _allowedCurrencies = {'USD', 'EUR', 'CZK', 'PLN', 'UAH'};

// ---------------------------------------------------------------------------
// Menu cache (disk)
// ---------------------------------------------------------------------------

class MenuCache {
  final Directory _dir;

  MenuCache()
      : _dir = Directory(
          '${File(Platform.script.toFilePath()).parent.parent.path}/$_menuCacheDir',
        ) {
    _dir.createSync(recursive: true);
  }

  String _fileNameFor(String url) {
    final sanitized = url
        .replaceAll(RegExp(r'https?://'), '')
        .replaceAll(RegExp(r'[^\w]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .toLowerCase();
    return '$sanitized.json';
  }

  File _fileFor(String url) => File('${_dir.path}/${_fileNameFor(url)}');

  List<MenuItem>? read(String url) {
    final file = _fileFor(url);
    if (!file.existsSync()) return null;
    print('Menu cache hit: ${file.path}');
    final raw = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    return raw.map((e) => MenuItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  void write(String url, List<MenuItem> items) {
    final file = _fileFor(url);
    file.writeAsStringSync(jsonEncode(items.map((e) => e.toJson()).toList()));
    print('Menu cached: ${file.path}');
  }
}

// ---------------------------------------------------------------------------
// Exchange rate cache
// ---------------------------------------------------------------------------

class _CachedRates {
  final ExchangeRates rates;
  final DateTime fetchedAt;

  _CachedRates(this.rates) : fetchedAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(fetchedAt) > _cacheTtl;
}

class ExchangeRateCache {
  final Map<String, _CachedRates> _cache = {};

  Future<ExchangeRates> getRates(String base) async {
    final cached = _cache[base];
    if (cached != null && !cached.isExpired) return cached.rates;

    print('Fetching exchange rates for base=$base');
    final response =
        await http.get(Uri.parse('$_exchangeRateApiUrl/$base'));

    if (response.statusCode != 200) {
      throw Exception(
          'Exchange rate API error: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final rates = ExchangeRates.fromJson(json);
    _cache[base] = _CachedRates(rates);
    return rates;
  }
}

// ---------------------------------------------------------------------------
// Server
// ---------------------------------------------------------------------------

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
  final rateCache = ExchangeRateCache();
  final menuCache = MenuCache();
  final router = Router();

  router.post('/scrape', (Request request) async {
    final body = await request.readAsString();
    final requestJson = jsonDecode(body) as Map<String, dynamic>;
    final url = requestJson['url'] as String;

    // Check disk cache first
    var items = menuCache.read(url);

    if (items == null) {
      // Forward to Python scraper
      final scraperResponse = await http.post(
        Uri.parse('$_scraperUrl/scrape'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (scraperResponse.statusCode != 200) {
        return Response(
          scraperResponse.statusCode,
          body: scraperResponse.body,
          headers: {'Content-Type': 'application/json'},
        );
      }

      final rawItems = jsonDecode(scraperResponse.body) as List<dynamic>;
      items = rawItems
          .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
          .toList();
      menuCache.write(url, items);
    }

    final base = items.firstWhere((i) => i.currency.isNotEmpty,
            orElse: () => const MenuItem(name: '', currency: 'USD'))
        .currency;

    // Fetch exchange rates (cached)
    final ExchangeRates exchangeRates;
    try {
      exchangeRates = await rateCache.getRates(base);
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    // Filter rates to allowed currencies only (always include base)
    final filteredRates = Map.fromEntries(
      exchangeRates.rates.entries
          .where((e) => _allowedCurrencies.contains(e.key)),
    );
    final filteredExchangeRates = ExchangeRates(
      base: exchangeRates.base,
      rates: filteredRates,
    );

    final scrapeResponse = ScrapeResponse(
      items: items,
      exchangeRates: filteredExchangeRates,
    );

    return Response.ok(
      jsonEncode(scrapeResponse.toJson()),
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

  final server =
      await shelf_io.serve(handler, InternetAddress.anyIPv4, _port);
  print('Backend running on http://localhost:${server.port}');
}
