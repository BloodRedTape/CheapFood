import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/restaurants_cubit.dart';
import '../cubit/scrape_cubit.dart';

/// Base widget that rebuilds only when the entry for [url] changes.
/// Override [buildEntry] instead of [build].
abstract class RestaurantWidget extends StatelessWidget {
  final String url;

  const RestaurantWidget({super.key, required this.url});

  /// Called when the entry for [url] has changed and a rebuild is needed.
  Widget buildEntry(BuildContext context, RestaurantEntry entry);

  /// Override to customize when to rebuild. By default rebuilds on any change to the entry.
  bool shouldRebuild(RestaurantEntry prev, RestaurantEntry next) => true;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RestaurantsCubit, RestaurantsState>(
      buildWhen: (prev, next) {
        final p = prev.find(url);
        final n = next.find(url);
        if (p == null && n == null) return false;
        if (p == null || n == null) return true;
        return shouldRebuild(p, n);
      },
      builder: (context, state) {
        final entry = state.find(url);
        if (entry == null) return const SizedBox.shrink();
        return buildEntry(context, entry);
      },
    );
  }
}

/// Mixin with common [shouldRebuild] predicates for convenience.
mixin RestaurantWidgetPredicates {
  static bool infoChanged(RestaurantEntry p, RestaurantEntry n) =>
      p.info.name != n.info.name ||
      p.info.totalItems != n.info.totalItems ||
      p.info.itemsWithPrice != n.info.itemsWithPrice;

  static bool scrapeStateChanged(RestaurantEntry p, RestaurantEntry n) =>
      p.scrapeState.runtimeType != n.scrapeState.runtimeType ||
      _scrapeStateValue(p.scrapeState) != _scrapeStateValue(n.scrapeState);

  static bool loadingChanged(RestaurantEntry p, RestaurantEntry n) =>
      _isLoading(p.scrapeState) != _isLoading(n.scrapeState);

  static bool _isLoading(ScrapeState s) => s is ScrapeLoading || s is ScrapeStreaming;

  static String? _scrapeStateValue(ScrapeState s) =>
      s is ScrapeStreaming ? s.message : null;
}
