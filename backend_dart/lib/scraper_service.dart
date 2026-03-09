import 'dart:async';
import 'dart:io';

import 'package:common_dart/common_dart.dart';

import 'config.dart';
import 'exchange_rate_cache.dart';
import 'menu_cache.dart';
import 'translation_service.dart';

/// Handles scraping, caching, translation, exchange rates, and deduplication.
///
/// All clients for the same URL receive events from the same broadcast stream —
/// there is no "primary" vs "secondary" client distinction.
class ScraperService {
  final MenuCache _menuCache;
  final ExchangeRateCache _rateCache;
  final TranslationService _translationService;

  /// In-flight scrapes keyed by URL. The broadcast controller emits raw SSE bytes.
  final Map<String, StreamController<List<int>>> _inFlight = {};

  ScraperService({
    required MenuCache menuCache,
    required ExchangeRateCache rateCache,
    required TranslationService translationService,
  })  : _menuCache = menuCache,
        _rateCache = rateCache,
        _translationService = translationService;

  /// Returns a single-subscription stream of SSE bytes for the given scrape request.
  ///
  /// If a scrape is already in flight for [url], the client is joined to the
  /// existing broadcast stream. Otherwise a new scrape is started.
  Stream<List<int>> scrape({
    required String url,
    required String requestBody,
    String? language,
    bool forceRefresh = false,
  }) {
    if (forceRefresh) _menuCache.clearUrl(url);

    final outputController = StreamController<List<int>>();

    // Cache hit — serve without touching the deduplicator.
    final translatedCached = language != null && language.isNotEmpty ? _menuCache.readTranslated(url, language) : null;
    if (translatedCached != null) {
      final cachedInfo = _menuCache.readRestaurantInfo(url) ?? const RestaurantInfo();
      _finishWithCategories(translatedCached, restaurantInfo: cachedInfo, url: url, language: language, output: outputController).catchError((Object e) {
        print('Finish error (translated cache): $e');
        _addError(outputController, 'Scrape failed');
      });
      return outputController.stream;
    }

    final originalCached = _menuCache.readOriginal(url);
    if (originalCached != null) {
      final cachedInfo = _menuCache.readRestaurantInfo(url) ?? const RestaurantInfo();
      _finishWithCategories(originalCached, restaurantInfo: cachedInfo, url: url, language: language, output: outputController).catchError((Object e) {
        print('Finish error (original cache): $e');
        _addError(outputController, 'Scrape failed');
      });
      return outputController.stream;
    }

    // Join existing in-flight scrape or start a new one.
    final broadcast = _inFlight[url];
    if (broadcast != null) {
      print('Scrape dedup: joining in-flight scrape for $url');
      _pipeIntoClosed(broadcast.stream, outputController);
      return outputController.stream;
    }

    // Start a new scrape — all clients (including this one) subscribe to the broadcast.
    final newBroadcast = StreamController<List<int>>.broadcast();
    _inFlight[url] = newBroadcast;
    _pipeIntoClosed(newBroadcast.stream, outputController);
    _runScrape(url: url, requestBody: requestBody, language: language, broadcast: newBroadcast);
    return outputController.stream;
  }

  /// Pipes [source] into [output], closing [output] when [source] is done.
  void _pipeIntoClosed(Stream<List<int>> source, StreamController<List<int>> output) {
    source.listen(
      (chunk) {
        if (!output.isClosed) output.add(chunk);
      },
      onError: (Object e) {
        print('Broadcast stream error: $e');
        _addError(output, 'Scrape failed');
      },
      onDone: () {
        if (!output.isClosed) output.close();
      },
    );
  }

  void _emit(StreamController<List<int>> controller, ScraperEvent event) {
    if (!controller.isClosed) controller.add(event.toSse());
  }

  void _addError(StreamController<List<int>> controller, String message) {
    _emit(controller, ScraperErrorEvent(message));
    if (!controller.isClosed) controller.close();
  }

  Future<void> _runScrape({
    required String url,
    required String requestBody,
    required String? language,
    required StreamController<List<int>> broadcast,
  }) async {
    try {
      final uri = Uri.parse('$scraperUrl/scrape/stream');
      final ioClient = HttpClient()..autoUncompress = false;
      final ioRequest = await ioClient.postUrl(uri);
      ioRequest.headers.set('Content-Type', 'application/json');
      ioRequest.write(requestBody);
      final ioResponse = await ioRequest.close();

      await for (final event in ScraperEvent.parseStream(ioResponse)) {
        if (broadcast.isClosed) break;
        if (event is ScraperProgressEvent) {
          _emit(broadcast, event);
        } else if (event is ScraperErrorEvent) {
          _emit(broadcast, event);
          ioClient.close();
          await broadcast.close();
          _inFlight.remove(url);
          return;
        } else if (event is ScraperResultEvent) {
          _menuCache.writeOriginal(url, event.categories);
          _menuCache.writeRestaurantInfo(url, event.restaurantInfo);
          ioClient.close();
          await _finishWithCategories(event.categories, restaurantInfo: event.restaurantInfo, url: url, language: language, output: broadcast);
          await broadcast.close();
          _inFlight.remove(url);
          return;
        }
      }

      // Stream ended without result or error.
      ioClient.close();
      await broadcast.close();
      _inFlight.remove(url);
    } catch (e) {
      print('Scrape forward error: $e');
      _emit(broadcast, ScraperErrorEvent('Scrape failed'));
      if (!broadcast.isClosed) {
        await broadcast.close();
        _inFlight.remove(url);
      }
    }
  }

  Future<void> _finishWithCategories(
    List<MenuCategory> categories, {
    required RestaurantInfo restaurantInfo,
    required String url,
    required String? language,
    required StreamController<List<int>> output,
  }) async {
    if (language != null && language.isNotEmpty) {
      final cached = _menuCache.readTranslated(url, language);
      if (cached != null) {
        categories = cached;
      } else {
        try {
          _emit(output, ScraperProgressEvent('Translating menu to $language...'));
          categories = await _translationService.translate(language: language, categories: categories);
          _menuCache.writeTranslated(url, language, categories);
        } catch (e) {
          print('Translation error: $e');
          _addError(output, 'Translation failed');
          return;
        }
      }
    }

    final base = categories
        .expand((c) => c.items)
        .expand((i) => i.variations)
        .firstWhere((v) => v.currency.isNotEmpty, orElse: () => const MenuItemVariation(currency: 'USD'))
        .currency;

    _emit(output, ScraperProgressEvent('Fetching exchange rates for $base...'));
    try {
      final raw = await _rateCache.getRates(base);
      final filteredRates = Map.fromEntries(raw.rates.entries.where((e) => allowedCurrencies.contains(e.key)));
      final exchangeRates = ExchangeRates(base: raw.base, rates: filteredRates);
      _emit(output, ScraperSaturatedResultEvent(ScrapeResponse(categories: categories, exchangeRates: exchangeRates, restaurantInfo: restaurantInfo)));
    } catch (e) {
      print('Exchange rates error: $e');
      _emit(output, ScraperErrorEvent('Exchange rates failed'));
    }
    if (!output.isClosed) await output.close();
  }
}
