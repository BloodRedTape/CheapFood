import 'package:common_dart/common_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../cubit/scrape_cubit.dart';

class MenuScrapeScreen extends StatefulWidget {
  const MenuScrapeScreen({super.key});

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
  final TextEditingController _urlController = TextEditingController();
  String _selectedLanguage = '';

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    context.read<ScrapeCubit>().scrape(_urlController.text, language: _selectedLanguage.isEmpty ? null : _selectedLanguage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Stupid Me', style: ShadTheme.of(context).textTheme.h2),
                const Spacer(),
                ShadSelect<String>(
                  initialValue: _selectedLanguage,
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedLanguage = value);
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
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ShadInput(controller: _urlController, placeholder: const Text('https://example.com/menu'), onSubmitted: (_) => _submit(context)),
                ),
                const SizedBox(width: 12),
                BlocBuilder<ScrapeCubit, ScrapeState>(
                  buildWhen: (prev, curr) => (prev is ScrapeLoading) != (curr is ScrapeLoading),
                  builder: (context, state) => ShadButton(onPressed: state is ScrapeLoading ? null : () => _submit(context), child: const Text('Search')),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: BlocBuilder<ScrapeCubit, ScrapeState>(
                builder:
                    (context, state) => switch (state) {
                      ScrapeInitial() => const SizedBox.shrink(),
                      ScrapeLoading() => const Center(child: CircularProgressIndicator()),
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
      options: options.map((c) => ShadOption(value: c, child: Text(c))).toList(),
      selectedOptionBuilder: (context, value) => Text(value),
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
            Expanded(
              child: _CategoryTabView(state: cubitState, categories: categories),
            ),
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
          tabs: widget.categories
              .map((c) => Tab(text: c.name ?? 'Menu'))
              .toList(),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: widget.categories.map((category) {
              return ListView.separated(
                padding: const EdgeInsets.only(top: 12),
                itemCount: category.items.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final item = category.items[index];
                  return _MenuItemCard(
                    item: item,
                    convertedPrice: widget.state.convertPrice(item.price, item.currency),
                    displayCurrency: widget.state.selectedCurrency,
                  );
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
  final double? convertedPrice;
  final String displayCurrency;

  const _MenuItemCard({required this.item, required this.convertedPrice, required this.displayCurrency});

  String? get _unitLabel {
    if (item.unitSize == null && item.unit == null) return null;
    final size = item.unitSize != null
        ? (item.unitSize! % 1 == 0 ? item.unitSize!.toInt().toString() : item.unitSize!.toString())
        : null;
    if (size != null && item.unit != null) return '$size ${item.unit}';
    return size ?? item.unit;
  }

  @override
  Widget build(BuildContext context) {
    final unitLabel = _unitLabel;
    return ShadCard(
      child: Row(
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
            children: [
              if (convertedPrice != null)
                Text('${convertedPrice!.toStringAsFixed(2)} $displayCurrency', style: ShadTheme.of(context).textTheme.p.copyWith(fontWeight: FontWeight.bold)),
              if (unitLabel != null)
                Text(unitLabel, style: ShadTheme.of(context).textTheme.muted),
            ],
          ),
        ],
      ),
    );
  }
}
