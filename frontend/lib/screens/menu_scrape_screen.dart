import 'package:common_dart/common_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../cubit/scrape_cubit.dart';

String _restaurantName(String url) {
  final host = Uri.tryParse(url)?.host ?? url;
  final parts = host.split('.').where((p) => p != 'www').toList();
  return parts.isNotEmpty ? parts.first : host;
}

class MenuScrapeScreen extends StatefulWidget {
  final String? restaurantUrl;

  const MenuScrapeScreen({super.key, this.restaurantUrl});

  @override
  State<MenuScrapeScreen> createState() => _MenuScrapeScreenState();
}

const List<(String, String, String)> _languages = [
  ('🌐', 'Original', ''),
  ('🇬🇧', 'English', 'en'),
  ('🇷🇺', 'Russian', 'ru'),
  ('🇨🇿', 'Czech', 'cs'),
  ('🇺🇦', 'Ukrainian', 'uk'),
  ('🇵🇱', 'Polish', 'pl'),
];

class _MenuScrapeScreenState extends State<MenuScrapeScreen> {
  String _selectedLanguage = '';

  @override
  Widget build(BuildContext context) {
    final title = widget.restaurantUrl != null ? _restaurantName(widget.restaurantUrl!) : '';
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ShadButton.ghost(onPressed: () => Navigator.of(context).pop(), child: const Icon(Icons.arrow_back)),
                const SizedBox(width: 8),
                Flexible(child: Text(title, style: ShadTheme.of(context).textTheme.h2, overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                ShadSelect<String>(
                  initialValue: _selectedLanguage,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedLanguage = value);
                      if (widget.restaurantUrl != null) {
                        context.read<ScrapeCubit>().scrape(widget.restaurantUrl!, language: value.isEmpty ? null : value);
                      }
                    }
                  },
                  options: _languages.map((l) => ShadOption(value: l.$3, child: Text('${l.$1} ${l.$2}'))).toList(),
                  selectedOptionBuilder: (context, value) {
                    final flag = _languages.firstWhere((l) => l.$3 == value, orElse: () => _languages.first).$1;
                    return Text(flag);
                  },
                ),
                const SizedBox(width: 8),
                const _CurrencySelect(),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: BlocBuilder<ScrapeCubit, ScrapeState>(
                builder:
                    (context, state) => switch (state) {
                      ScrapeInitial() => const SizedBox.shrink(),
                      ScrapeLoading() => const Center(child: CircularProgressIndicator()),
                      ScrapeStreaming(:final message) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(message, style: ShadTheme.of(context).textTheme.muted),
                          ],
                        ),
                      ),
                      ScrapeFailure(:final message) => ShadAlert.destructive(title: const Text('Error'), description: Text(message)),
                      ScrapeSuccess() => _SuccessView(state: state),
                    },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrencySelect extends StatelessWidget {
  const _CurrencySelect();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ScrapeCubit>();
    final options = supportedCurrencies.toList()..sort();
    return ShadSelect<String>(
      initialValue: cubit.selectedCurrency,
      onChanged: (value) {
        if (value != null) cubit.selectCurrency(value);
      },
      options: [const ShadOption(value: '', child: Text('🌐 Original')), ...options.map((c) => ShadOption(value: c, child: Text(c)))],
      selectedOptionBuilder: (context, value) => Text(value.isEmpty ? '🌐' : value),
    );
  }
}

class _SuccessView extends StatelessWidget {
  final ScrapeSuccess state;

  const _SuccessView({required this.state});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ScrapeCubit, ScrapeState>(
      builder: (context, cubitState) {
        if (cubitState is! ScrapeSuccess) return const SizedBox.shrink();
        final categories = cubitState.categories;
        final totalItems = categories.fold(0, (sum, c) => sum + c.items.length);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$totalItems items found', style: ShadTheme.of(context).textTheme.muted),
            const SizedBox(height: 12),
            Expanded(child: _CategoryTabView(state: cubitState, categories: categories)),
          ],
        );
      },
    );
  }
}

class _CategoryTabView extends StatefulWidget {
  final ScrapeSuccess state;
  final List<MenuCategory> categories;

  const _CategoryTabView({required this.state, required this.categories});

  @override
  State<_CategoryTabView> createState() => _CategoryTabViewState();
}

class _CategoryTabViewState extends State<_CategoryTabView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.categories.length, vsync: this);
  }

  @override
  void didUpdateWidget(_CategoryTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categories.length != widget.categories.length) {
      _tabController.dispose();
      _tabController = TabController(length: widget.categories.length, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.categories.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: widget.categories.map((c) => Tab(text: c.name ?? 'Menu')).toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children:
                widget.categories.map((category) {
                  return ListView.separated(
                    padding: const EdgeInsets.only(top: 12),
                    itemCount: category.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = category.items[index];
                      return _MenuItemCard(item: item, state: widget.state);
                    },
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final ScrapeSuccess state;

  const _MenuItemCard({required this.item, required this.state});

  String? _unitLabel(MenuItemVariation v) {
    if (v.unitSize == null && v.unit == null) return null;
    final size = v.unitSize != null ? (v.unitSize! % 1 == 0 ? v.unitSize!.toInt().toString() : v.unitSize!.toString()) : null;
    if (size != null && v.unit != null) return '$size ${v.unit}';
    return size ?? v.unit;
  }

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      padding: EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: ShadTheme.of(context).textTheme.p),
                if (item.description != null) Text(item.description!, style: ShadTheme.of(context).textTheme.muted),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children:
                item.variations.map((v) {
                  final convertedPrice = state.convertPrice(v.price, v.currency);
                  final unitLabel = _unitLabel(v);
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (unitLabel != null) ...[Text(unitLabel, style: ShadTheme.of(context).textTheme.muted), const SizedBox(width: 6)],
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
