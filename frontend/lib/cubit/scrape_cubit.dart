import 'dart:convert' show jsonEncode;

import 'package:common_dart/common_dart.dart';
import 'package:fetch_client/fetch_client.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http; // needed for http.Request

import '../config.dart';

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
  final RestaurantInfo restaurantInfo;
  final String selectedCurrency;
  final String language;

  ScrapeSuccess({required this.categories, required this.exchangeRates, required this.restaurantInfo, required this.selectedCurrency, required this.language});

  ScrapeSuccess withCurrency(String currency) =>
      ScrapeSuccess(categories: categories, exchangeRates: exchangeRates, restaurantInfo: restaurantInfo, selectedCurrency: currency, language: language);

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
  String selectedCurrency = '';
  final String token;

  ScrapeCubit({required this.token}) : super(ScrapeInitial());

  Future<void> scrape(String url, {String? language, bool forceRefresh = false}) async {
    if (url.trim().isEmpty) return;

    emit(ScrapeLoading());

    try {
      final requestBody = jsonEncode(ScrapeRequest(url: url.trim(), language: language, forceRefresh: forceRefresh).toJson());

      // Phase 1: stream progress events from scraper
      final streamRequest = http.Request('POST', Uri.parse('$backendUrl/scrape/stream'))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer $token'
        ..body = requestBody;

      final streamedResponse = await FetchClient(mode: RequestMode.cors).send(streamRequest);

      if (streamedResponse.statusCode != 200) {
        emit(ScrapeFailure('Server error: ${streamedResponse.statusCode}'));
        return;
      }

      await for (final event in ScraperEvent.parseStream(streamedResponse.stream)) {
        switch (event) {
          case ScraperProgressEvent(:final message):
            emit(ScrapeStreaming(message));
          case ScraperErrorEvent(:final message):
            emit(ScrapeFailure(message));
            return;
          case ScraperSaturatedResultEvent(:final response):
            emit(ScrapeSuccess(
              categories: response.categories,
              exchangeRates: response.exchangeRates,
              restaurantInfo: response.restaurantInfo,
              selectedCurrency: selectedCurrency,
              language: language ?? '',
            ));
            return;
          case ScraperResultEvent():
            break; // never sent by backend to frontend
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
