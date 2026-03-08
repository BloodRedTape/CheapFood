import 'dart:async';

/// Deduplicates in-flight scrape requests for the same URL.
///
/// When a scrape is already running for a URL, subsequent requests subscribe
/// to the same broadcast stream instead of launching a new scrape.
/// The stream emits raw SSE-encoded bytes (progress/result/error events).
class ScrapeDeduplicator {
  final Map<String, _InFlightScrape> _inFlight = {};

  /// Returns true if a scrape is currently in progress for [url].
  bool isInFlight(String url) => _inFlight.containsKey(url);

  /// Registers a new in-flight scrape for [url] and returns the broadcast
  /// [StreamController] to write events into.
  ///
  /// The caller is responsible for closing the controller when done.
  /// Call [complete] to clean up after the scrape finishes.
  StreamController<List<int>> register(String url) {
    assert(!_inFlight.containsKey(url), 'Scrape already in flight for $url');
    final controller = StreamController<List<int>>.broadcast();
    _inFlight[url] = _InFlightScrape(controller);
    return controller;
  }

  /// Subscribes to the in-flight scrape stream for [url].
  ///
  /// Returns null if no scrape is in flight for [url].
  Stream<List<int>>? subscribe(String url) => _inFlight[url]?.controller.stream;

  /// Removes the in-flight entry for [url] after the scrape completes.
  void complete(String url) {
    _inFlight.remove(url);
  }
}

class _InFlightScrape {
  final StreamController<List<int>> controller;
  _InFlightScrape(this.controller);
}
