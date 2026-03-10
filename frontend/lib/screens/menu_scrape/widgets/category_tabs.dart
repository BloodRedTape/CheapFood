import 'package:common_dart/common_dart.dart';
import 'package:flutter/material.dart';

/// Sliver persistent header that sticks below the SliverAppBar.
/// Shows scrollable category tabs.
class CategoryTabsHeader extends SliverPersistentHeaderDelegate {
  final TabController tabController;
  final List<MenuCategory> categories;

  static const double height = 56;

  CategoryTabsHeader({required this.tabController, required this.categories});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  bool shouldRebuild(CategoryTabsHeader oldDelegate) =>
      oldDelegate.categories != categories || oldDelegate.tabController != tabController;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surface,
      child: Column(
        children: [
          TabBar(
            controller: tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tabs: categories.map((c) => Tab(text: c.name ?? 'Menu')).toList(),
          ),
          const Divider(height: 1, thickness: 1),
        ],
      ),
    );
  }
}
