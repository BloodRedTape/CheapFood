import 'dart:convert';

import 'package:common_dart/common_dart.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

sealed class ScrapeState {}

final class ScrapeInitial extends ScrapeState {}

final class ScrapeLoading extends ScrapeState {}

final class ScrapeSuccess extends ScrapeState {
  final List<MenuItem> items;
  final ExchangeRates exchangeRates;
  final String selectedCurrency;

  ScrapeSuccess({
    required this.items,
    required this.exchangeRates,
    required this.selectedCurrency,
  });

  ScrapeSuccess withCurrency(String currency) => ScrapeSuccess(
        items: items,
        exchangeRates: exchangeRates,
        selectedCurrency: currency,
      );

  /// Converts a price from the base currency to [selectedCurrency].
  double? convertPrice(double? price, String itemCurrency) {
    if (price == null) return null;
    if (itemCurrency == selectedCurrency) return price;

    final rates = exchangeRates.rates;
    // Convert item currency → base, then base → selected
    final toBase = itemCurrency == exchangeRates.base
        ? price
        : price / (rates[itemCurrency] ?? 1.0);
    return toBase * (rates[selectedCurrency] ?? 1.0);
  }
}

final class ScrapeFailure extends ScrapeState {
  final String message;
  ScrapeFailure(this.message);
}

class ScrapeCubit extends Cubit<ScrapeState> {
  static const String _backendUrl = 'http://localhost:8080';

  ScrapeCubit() : super(ScrapeInitial());

  Future<void> scrape(String url) async {
    if (url.trim().isEmpty) return;

    emit(ScrapeLoading());

    try {
      final request = ScrapeRequest(url: url.trim());
      final response = await http.post(
        Uri.parse('$_backendUrl/scrape'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(request.toJson()),
      );

      if (response.statusCode == 200) {
        final scrapeResponse = ScrapeResponse.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>);
        emit(ScrapeSuccess(
          items: scrapeResponse.items,
          exchangeRates: scrapeResponse.exchangeRates,
          selectedCurrency: scrapeResponse.exchangeRates.base,
        ));
      } else {
        emit(ScrapeFailure('Server error: ${response.statusCode}'));
      }
    } catch (e) {
      emit(ScrapeFailure('Connection failed: $e'));
    }
  }

  void selectCurrency(String currency) {
    final current = state;
    if (current is ScrapeSuccess) {
      emit(current.withCurrency(currency));
    }
  }
}
