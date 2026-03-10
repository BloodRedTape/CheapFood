import 'package:common_dart/common_dart.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../cubit/scrape_cubit.dart';

class MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final ScrapeSuccess state;

  const MenuItemCard({super.key, required this.item, required this.state});

  String? _unitLabel(MenuItemVariation v) {
    if (v.unitSize == null && v.unit == null) return null;
    final size = v.unitSize != null
        ? (v.unitSize! % 1 == 0 ? v.unitSize!.toInt().toString() : v.unitSize!.toString())
        : null;
    if (size != null && v.unit != null) return '$size ${v.unit}';
    return size ?? v.unit;
  }

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: ShadTheme.of(context).textTheme.p),
                if (item.description != null)
                  Text(item.description!, style: ShadTheme.of(context).textTheme.muted),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: item.variations.map((v) {
              final convertedPrice = state.convertPrice(v.price, v.currency);
              final unitLabel = _unitLabel(v);
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (unitLabel != null) ...[
                    Text(unitLabel, style: ShadTheme.of(context).textTheme.muted),
                    const SizedBox(width: 6),
                  ],
                  if (convertedPrice != null)
                    Text(
                      '${convertedPrice.toStringAsFixed(2)} ${state.priceLabel(v.currency)}',
                      style: ShadTheme.of(context).textTheme.p.copyWith(fontWeight: FontWeight.bold),
                    ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
