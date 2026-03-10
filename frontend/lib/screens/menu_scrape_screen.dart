import 'package:common_dart/common_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../cubit/restaurants_cubit.dart';
import '../cubit/scrape_cubit.dart';
import '../widgets/restaurant_widget.dart';

String _restaurantNameFromUrl(String url) {
  final host = Uri.tryParse(url)?.host ?? url;
  final parts = host.split('.').where((p) => p != 'www').toList();
  return parts.isNotEmpty ? parts.first : host;
}

const List<(String, String, String)> _languages = [
  ('🌐', 'Original', ''),
  ('🇬🇧', 'English', 'en'),
  ('🇷🇺', 'Russian', 'ru'),
  ('🇨🇿', 'Czech', 'cs'),
  ('🇺🇦', 'Ukrainian', 'uk'),
  ('🇵🇱', 'Polish', 'pl'),
];

class MenuScrapeScreen extends StatefulWidget {
  final String restaurantUrl;

  const MenuScrapeScreen({super.key, required this.restaurantUrl});

  @override
  State<MenuScrapeScreen> createState() => _MenuScrapeScreenState();
}

class _MenuScrapeScreenState extends State<MenuScrapeScreen> {
  String _selectedLanguage = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MenuScrapeHeader(
              url: widget.restaurantUrl,
              selectedLanguage: _selectedLanguage,
              onLanguageChanged: (lang) {
                setState(() => _selectedLanguage = lang);
                context.read<RestaurantsCubit>().scrape(widget.restaurantUrl, language: lang.isEmpty ? null : lang);
              },
            ),
            const SizedBox(height: 16),
            Expanded(child: _MenuScrapeBody(url: widget.restaurantUrl)),
          ],
        ),
      ),
    );
  }
}

class _MenuScrapeHeader extends RestaurantWidget {
  final String selectedLanguage;
  final ValueChanged<String> onLanguageChanged;

  const _MenuScrapeHeader({
    required super.url,
    required this.selectedLanguage,
    required this.onLanguageChanged,
  });

  @override
  bool shouldRebuild(RestaurantEntry prev, RestaurantEntry next) =>
      RestaurantWidgetPredicates.scrapeStateChanged(prev, next);

  @override
  Widget buildEntry(BuildContext context, RestaurantEntry entry) {
    final fallbackTitle = _restaurantNameFromUrl(url);
    final scrapeState = entry.scrapeState;
    final name = scrapeState is ScrapeSuccess ? (scrapeState.restaurantInfo.name ?? fallbackTitle) : fallbackTitle;
    final selectedCurrency = context.read<RestaurantsCubit>().selectedCurrency(url);
    final options = supportedCurrencies.toList()..sort();

    return Row(
      children: [
        ShadButton.ghost(onPressed: () => Navigator.of(context).pop(), child: const Icon(Icons.arrow_back)),
        const SizedBox(width: 8),
        Flexible(child: Text(name, style: ShadTheme.of(context).textTheme.h2, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        ShadSelect<String>(
          initialValue: selectedLanguage,
          onChanged: (value) { if (value != null) onLanguageChanged(value); },
          options: _languages.map((l) => ShadOption(value: l.$3, child: Text('${l.$1} ${l.$2}'))).toList(),
          selectedOptionBuilder: (context, value) {
            final flag = _languages.firstWhere((l) => l.$3 == value, orElse: () => _languages.first).$1;
            return Text(flag);
          },
        ),
        const SizedBox(width: 8),
        ShadSelect<String>(
          initialValue: selectedCurrency,
          onChanged: (value) {
            if (value != null) context.read<RestaurantsCubit>().selectCurrency(url, value);
          },
          options: [
            const ShadOption(value: '', child: Text('🌐 Original')),
            ...options.map((c) => ShadOption(value: c, child: Text(c))),
          ],
          selectedOptionBuilder: (context, value) => Text(value.isEmpty ? '🌐' : value),
        ),
      ],
    );
  }
}

class _MenuScrapeBody extends RestaurantWidget {
  const _MenuScrapeBody({required super.url});

  @override
  bool shouldRebuild(RestaurantEntry prev, RestaurantEntry next) =>
      RestaurantWidgetPredicates.scrapeStateChanged(prev, next);

  @override
  Widget buildEntry(BuildContext context, RestaurantEntry entry) {
    return switch (entry.scrapeState) {
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
      ScrapeFailure(:final message) => ShadAlert.destructive(
        title: const Text('Error'),
        description: Text(message),
      ),
      ScrapeSuccess() => _SuccessView(url: url, state: entry.scrapeState as ScrapeSuccess),
    };
  }
}

class _SuccessView extends StatelessWidget {
  final String url;
  final ScrapeSuccess state;

  const _SuccessView({required this.url, required this.state});

  @override
  Widget build(BuildContext context) {
    final categories = state.categories;
    final totalItems = categories.fold(0, (sum, c) => sum + c.items.length);
    final itemsWithPrice = categories.fold(
      0,
      (sum, c) => sum + c.items.where((item) => item.variations.any((v) => v.price != null)).length,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$totalItems items found, $itemsWithPrice with price', style: ShadTheme.of(context).textTheme.muted),
        const SizedBox(height: 12),
        Expanded(child: _CategoryTabView(state: state, categories: categories, restaurantUrl: url)),
      ],
    );
  }
}

class _CategoryTabView extends StatefulWidget {
  final ScrapeSuccess state;
  final List<MenuCategory> categories;
  final String restaurantUrl;

  const _CategoryTabView({required this.state, required this.categories, required this.restaurantUrl});

  @override
  State<_CategoryTabView> createState() => _CategoryTabViewState();
}

class _CategoryTabViewState extends State<_CategoryTabView> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  int get _tabCount => widget.categories.length + 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
  }

  @override
  void didUpdateWidget(_CategoryTabView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categories.length != widget.categories.length) {
      _tabController.dispose();
      _tabController = TabController(length: _tabCount, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            const Tab(text: 'Info'),
            ...widget.categories.map((c) => Tab(text: c.name ?? 'Menu')),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _RestaurantInfoTab(info: widget.state.restaurantInfo, websiteUrl: widget.restaurantUrl),
              ...widget.categories.map((category) => ListView.separated(
                padding: const EdgeInsets.only(top: 12),
                itemCount: category.items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) => _MenuItemCard(item: category.items[index], state: widget.state),
              )),
            ],
          ),
        ),
      ],
    );
  }
}

class _RestaurantInfoTab extends StatelessWidget {
  final RestaurantInfo info;
  final String websiteUrl;

  const _RestaurantInfoTab({required this.info, required this.websiteUrl});

  static const _dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isEmpty = info.name == null &&
        info.phones.isEmpty &&
        info.address == null &&
        info.workingHours.isEmpty &&
        info.siteLanguage == null;
    return ListView(
      padding: const EdgeInsets.only(top: 16),
      children: [
        if (info.name != null) _InfoRow(label: 'Name', value: info.name!),
        _InfoLinkRow(label: 'Website', url: websiteUrl),
        if (info.address != null) _InfoRow(label: 'Address', value: info.address!),
        if (info.phones.isNotEmpty) _InfoRow(label: 'Phone', value: info.phones.join(', ')),
        if (info.workingHours.isNotEmpty)
          _InfoRow(
            label: 'Working hours',
            value: info.workingHours.map((d) => '${_dayNames[d.day]}: ${d.open ?? '?'}–${d.close ?? '?'}').join('\n'),
          ),
        if (info.siteLanguage != null) _InfoRow(label: 'Site language', value: info.siteLanguage!),
        if (isEmpty) Center(child: Text('No restaurant info available', style: theme.textTheme.muted)),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: theme.textTheme.muted)),
          Expanded(child: Text(value, style: theme.textTheme.p)),
        ],
      ),
    );
  }
}

class _InfoLinkRow extends StatelessWidget {
  final String label;
  final String url;

  const _InfoLinkRow({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 130, child: Text(label, style: theme.textTheme.muted)),
          Expanded(
            child: GestureDetector(
              onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              child: Text(
                url,
                style: theme.textTheme.p.copyWith(
                  color: theme.colorScheme.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
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
      padding: const EdgeInsets.all(16),
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
            children: item.variations.map((v) {
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
