import 'dart:convert';

import 'package:common_dart/common_dart.dart';
import 'package:fetch_client/fetch_client.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import 'scrape_cubit.dart';

/// One entry in the restaurants list: preview info + current scrape state.
final class RestaurantEntry {
  final RestaurantPreviewInfo info;
  final ScrapeState scrapeState;

  const RestaurantEntry({required this.info, required this.scrapeState});

  RestaurantEntry copyWith({RestaurantPreviewInfo? info, ScrapeState? scrapeState}) =>
      RestaurantEntry(info: info ?? this.info, scrapeState: scrapeState ?? this.scrapeState);
}

final class RestaurantsState {
  final List<RestaurantEntry> entries;

  const RestaurantsState(this.entries);

  List<String> get urls => entries.map((e) => e.info.url).toList();

  RestaurantsState withEntries(List<RestaurantEntry> entries) => RestaurantsState(entries);

  RestaurantsState updateScrapeState(String url, ScrapeState scrapeState) => RestaurantsState(
    entries.map((e) => e.info.url == url ? e.copyWith(scrapeState: scrapeState) : e).toList(),
  );

  RestaurantsState updateInfo(List<RestaurantPreviewInfo> infos) => RestaurantsState(
    infos.map((info) {
      final existing = entries.where((e) => e.info.url == info.url).firstOrNull;
      return RestaurantEntry(info: info, scrapeState: existing?.scrapeState ?? ScrapeInitial());
    }).toList(),
  );

  RestaurantEntry? find(String url) => entries.where((e) => e.info.url == url).firstOrNull;
}

List<RestaurantPreviewInfo> _parseRestaurants(Map<String, dynamic> data) {
  return (data['restaurants'] as List<dynamic>)
      .map((e) => RestaurantPreviewInfo.fromJson(e as Map<String, dynamic>))
      .toList();
}

class RestaurantsCubit extends Cubit<RestaurantsState> {
  final String token;

  // Per-URL selected currency, survives scrape restarts
  final _currencies = <String, String>{};

  RestaurantsCubit({required this.token}) : super(const RestaurantsState([])) {
    refresh();
  }

  Map<String, String> get _authHeaders => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  /// Fetch fresh restaurant list from backend (backgrounds info update only).
  Future<void> refresh() async {
    try {
      final response = await http.get(Uri.parse('$backendUrl/restaurants'), headers: _authHeaders);
      if (isClosed) return;
      if (response.statusCode == 200) {
        final infos = _parseRestaurants(jsonDecode(response.body) as Map<String, dynamic>);
        emit(state.updateInfo(infos));
      }
    } catch (_) {}
  }

  Future<void> addUrl(String url) async {
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/restaurants'),
        headers: _authHeaders,
        body: jsonEncode({'url': url}),
      );
      if (isClosed) return;
      if (response.statusCode == 200) {
        final infos = _parseRestaurants(jsonDecode(response.body) as Map<String, dynamic>);
        emit(state.updateInfo(infos));
      }
    } catch (_) {}
  }

  Future<void> removeUrl(String url) async {
    try {
      final request = http.Request('DELETE', Uri.parse('$backendUrl/restaurants'))
        ..headers.addAll(_authHeaders)
        ..body = jsonEncode({'url': url});
      final streamed = await http.Client().send(request);
      if (isClosed) return;
      if (streamed.statusCode == 200) {
        final body = await streamed.stream.bytesToString();
        final infos = _parseRestaurants(jsonDecode(body) as Map<String, dynamic>);
        emit(state.updateInfo(infos));
      }
    } catch (_) {}
  }

  /// Start scraping a restaurant. No-op if already in progress.
  Future<void> scrape(String url, {String? language}) async {
    final entry = state.find(url);
    if (entry == null) return;
    final current = entry.scrapeState;
    if (current is ScrapeLoading || current is ScrapeStreaming) return;

    _emitScrape(url, ScrapeLoading());

    try {
      final selectedCurrency = _currencies[url] ?? '';
      final requestBody = jsonEncode(
        ScrapeRequest(url: url, language: language).toJson(),
      );

      final streamRequest = http.Request('POST', Uri.parse('$backendUrl/scrape/stream'))
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer $token'
        ..body = requestBody;

      final streamedResponse = await FetchClient(mode: RequestMode.cors).send(streamRequest);

      if (isClosed) return;
      if (streamedResponse.statusCode != 200) {
        _emitScrape(url, ScrapeFailure('Server error: ${streamedResponse.statusCode}'));
        return;
      }

      await for (final event in ScraperEvent.parseStream(streamedResponse.stream)) {
        if (isClosed) return;
        switch (event) {
          case ScraperProgressEvent(:final message):
            _emitScrape(url, ScrapeStreaming(message));
          case ScraperErrorEvent(:final message):
            _emitScrape(url, ScrapeFailure(message));
            return;
          case ScraperSaturatedResultEvent(:final response):
            _emitScrape(url, ScrapeSuccess(
              categories: response.categories,
              exchangeRates: response.exchangeRates,
              restaurantInfo: response.restaurantInfo,
              selectedCurrency: selectedCurrency,
              language: language ?? '',
            ));
            // Refresh preview info after successful scrape
            refresh();
            return;
          case ScraperResultEvent():
            break;
        }
      }
    } catch (e) {
      if (!isClosed) _emitScrape(url, ScrapeFailure('Connection failed: $e'));
    }
  }

  void selectCurrency(String url, String currency) {
    _currencies[url] = currency;
    final entry = state.find(url);
    if (entry?.scrapeState is ScrapeSuccess) {
      _emitScrape(url, (entry!.scrapeState as ScrapeSuccess).withCurrency(currency));
    }
  }

  String selectedCurrency(String url) => _currencies[url] ?? '';

  void _emitScrape(String url, ScrapeState scrapeState) {
    emit(state.updateScrapeState(url, scrapeState));
  }
}
