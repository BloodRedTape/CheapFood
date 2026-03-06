import 'dart:convert';

import 'package:common_dart/common_dart.dart';
import 'package:fetch_client/fetch_client.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http; // needed for http.Request

sealed class ScrapeState {}

final class ScrapeInitial extends ScrapeState {}

final class ScrapeLoading extends ScrapeState {}

final class ScrapeStreaming extends ScrapeState {
  final String message;
  ScrapeStreaming(this.message);
}

final class ScrapeSuccess extends ScrapeState {
  final List<MenuCategory> categories;
  final ExchangeRates exchangeRates;
  final String selectedCurrency;
  final String language;

  ScrapeSuccess({required this.categories, required this.exchangeRates, required this.selectedCurrency, required this.language});

  ScrapeSuccess withCurrency(String currency) =>
      ScrapeSuccess(categories: categories, exchangeRates: exchangeRates, selectedCurrency: currency, language: language);

  /// Returns null if selectedCurrency is '' (show original).
  /// Otherwise converts [price] from [itemCurrency] to [selectedCurrency].
  double? convertPrice(double? price, String itemCurrency) {
    if (price == null) return null;
    if (selectedCurrency.isEmpty) return price;
    if (itemCurrency == selectedCurrency) return price;

    final rates = exchangeRates.rates;
    final toBase = itemCurrency == exchangeRates.base ? price : price / (rates[itemCurrency] ?? 1.0);
    return toBase * (rates[selectedCurrency] ?? 1.0);
  }

  /// The currency label to display next to the price.
  String priceLabel(String itemCurrency) => selectedCurrency.isEmpty ? itemCurrency : selectedCurrency;
}

final class ScrapeFailure extends ScrapeState {
  final String message;
  ScrapeFailure(this.message);
}

class ScrapeCubit extends Cubit<ScrapeState> {
  static const String _backendUrl = 'http://localhost:8080';

  String selectedCurrency = '';

  ScrapeCubit() : super(ScrapeInitial());

  Future<void> scrape(String url, {String? language, bool forceRefresh = false}) async {
    if (url.trim().isEmpty) return;

    emit(ScrapeLoading());

    try {
      final requestBody = jsonEncode(ScrapeRequest(url: url.trim(), language: language, forceRefresh: forceRefresh).toJson());

      // Phase 1: stream progress events from scraper
      final streamRequest = http.Request('POST', Uri.parse('$_backendUrl/scrape/stream'))
        ..headers['Content-Type'] = 'application/json'
        ..body = requestBody;

      final streamedResponse = await FetchClient(mode: RequestMode.cors).send(streamRequest);

      if (streamedResponse.statusCode != 200) {
        emit(ScrapeFailure('Server error: ${streamedResponse.statusCode}'));
        return;
      }

      final stream = streamedResponse.stream;

      String buffer = '';
      String? eventType;
      String? eventData;

      await for (final chunk in stream) {
        buffer += utf8.decode(chunk);
        final lines = buffer.split('\n');
        buffer = lines.last;

        for (final line in lines.sublist(0, lines.length - 1)) {
          if (line.startsWith('event: ')) {
            eventType = line.substring(7).trim();
          } else if (line.startsWith('data: ')) {
            eventData = line.substring(6).trim();
          } else if (line.isEmpty && eventType != null && eventData != null) {
            if (eventType == 'progress') {
              emit(ScrapeStreaming(eventData));
            } else if (eventType == 'error') {
              emit(ScrapeFailure(eventData));
              return;
            } else if (eventType == 'result') {
              final scrapeResponse = ScrapeResponse.fromJson(jsonDecode(eventData) as Map<String, dynamic>);
              emit(
                ScrapeSuccess(
                  categories: scrapeResponse.categories,
                  exchangeRates: scrapeResponse.exchangeRates,
                  selectedCurrency: selectedCurrency,
                  language: language ?? '',
                ),
              );
              return;
            }
            eventType = null;
            eventData = null;
          }
        }
      }
    } catch (e) {
      emit(ScrapeFailure('Connection failed: $e'));
    }
  }

  void selectCurrency(String currency) {
    selectedCurrency = currency;
    final current = state;
    if (current is ScrapeSuccess) {
      emit(current.withCurrency(currency));
    }
  }
}
