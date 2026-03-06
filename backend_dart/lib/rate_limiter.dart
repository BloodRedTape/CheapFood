class RateLimiter {
  final int maxRequests;
  final Duration window;

  RateLimiter({this.maxRequests = 10, this.window = const Duration(minutes: 1)});

  final _buckets = <String, List<DateTime>>{};

  /// Returns true if the request is allowed, false if rate limited.
  bool allow(String key) {
    final now = DateTime.now();
    final cutoff = now.subtract(window);
    final timestamps = _buckets[key] ?? [];
    timestamps.removeWhere((t) => t.isBefore(cutoff));
    if (timestamps.length >= maxRequests) return false;
    timestamps.add(now);
    _buckets[key] = timestamps;
    return true;
  }
}
