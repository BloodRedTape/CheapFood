import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../cubit/restaurants_cubit.dart';
import '../cubit/scrape_cubit.dart';
import 'restaurant_widget.dart';

class RestaurantCard extends RestaurantWidget {
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const RestaurantCard({required super.url, required this.onTap, required this.onDelete, super.key});

  @override
  bool shouldRebuild(RestaurantEntry prev, RestaurantEntry next) =>
      RestaurantWidgetPredicates.infoChanged(prev, next) ||
      RestaurantWidgetPredicates.loadingChanged(prev, next);

  @override
  Widget buildEntry(BuildContext context, RestaurantEntry entry) {
    final info = entry.info;
    final isLoading = entry.scrapeState is ScrapeLoading || entry.scrapeState is ScrapeStreaming;

    return ShadCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(info.name ?? url, style: ShadTheme.of(context).textTheme.p),
                      if (isLoading) ...[
                        const SizedBox(width: 8),
                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
                      ],
                    ],
                  ),
                  if (info.name != null)
                    Text(url, style: ShadTheme.of(context).textTheme.muted),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text('${info.itemsWithPrice}/${info.totalItems}', style: ShadTheme.of(context).textTheme.muted),
            ShadButton.ghost(
              onPressed: onDelete,
              child: const Icon(Icons.delete_outline, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}
