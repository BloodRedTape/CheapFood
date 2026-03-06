import 'dart:convert';

import 'package:common_dart/common_dart.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

class _CachedRates {
  final ExchangeRates rates;
  final DateTime fetchedAt;

  _CachedRates(this.rates) : fetchedAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(fetchedAt) > cacheTtl;
}

class ExchangeRateCache {
  final Map<String, _CachedRates> _cache = {};

  Future<ExchangeRates> getRates(String base) async {
    final cached = _cache[base];
    if (cached != null && !cached.isExpired) return cached.rates;

    print('Fetching exchange rates for base=$base');
    final response = await http.get(Uri.parse('$exchangeRateApiUrl/$base'));

    if (response.statusCode != 200) {
      throw Exception('Exchange rate API error: ${response.statusCode}');
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final rates = ExchangeRates.fromJson(json);
    _cache[base] = _CachedRates(rates);
    return rates;
  }
}
