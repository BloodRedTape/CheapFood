import 'package:common_dart/common_dart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../cubit/restaurants_cubit.dart';
import '../../cubit/scrape_cubit.dart';
import '../../widgets/restaurant_widget.dart';
import 'widgets/category_tabs.dart';
import 'widgets/menu_app_bar.dart';
import 'widgets/menu_item_card.dart';

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
    return BlocBuilder<RestaurantsCubit, RestaurantsState>(
      buildWhen: (prev, next) {
        final p = prev.find(widget.restaurantUrl);
        final n = next.find(widget.restaurantUrl);
        if (p == null && n == null) return false;
        if (p == null || n == null) return true;
        return RestaurantWidgetPredicates.scrapeStateChanged(p, n);
      },
      builder: (context, state) {
        final entry = state.find(widget.restaurantUrl);
        if (entry == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));

        final scrapeState = entry.scrapeState;
        final previewInfo = entry.info;
        final selectedCurrency = context.read<RestaurantsCubit>().selectedCurrency(widget.restaurantUrl);
        final currencyOptions = supportedCurrencies.toList()..sort();

        return Scaffold(
          body: switch (scrapeState) {
            ScrapeSuccess() => _SuccessScaffold(
                url: widget.restaurantUrl,
                previewInfo: previewInfo,
                state: scrapeState,
                selectedLanguage: _selectedLanguage,
                selectedCurrency: selectedCurrency,
                currencyOptions: currencyOptions,
                onLanguageChanged: (lang) {
                  setState(() => _selectedLanguage = lang);
                  context.read<RestaurantsCubit>().scrape(
                    widget.restaurantUrl,
                    language: lang.isEmpty ? null : lang,
                  );
                },
                onCurrencyChanged: (currency) {
                  context.read<RestaurantsCubit>().selectCurrency(widget.restaurantUrl, currency);
                },
              ),
            _ => _LoadingScaffold(
                url: widget.restaurantUrl,
                previewInfo: previewInfo,
                scrapeState: scrapeState,
                selectedLanguage: _selectedLanguage,
                selectedCurrency: selectedCurrency,
                currencyOptions: currencyOptions,
                onLanguageChanged: (lang) {
                  setState(() => _selectedLanguage = lang);
                  context.read<RestaurantsCubit>().scrape(
                    widget.restaurantUrl,
                    language: lang.isEmpty ? null : lang,
                  );
                },
                onCurrencyChanged: (currency) {
                  context.read<RestaurantsCubit>().selectCurrency(widget.restaurantUrl, currency);
                },
              ),
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Loading / error scaffold — no tabs, just app bar + centered status
// ---------------------------------------------------------------------------

class _LoadingScaffold extends StatelessWidget {
  final String url;
  final RestaurantPreviewInfo previewInfo;
  final ScrapeState scrapeState;
  final String selectedLanguage;
  final String selectedCurrency;
  final List<String> currencyOptions;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<String> onCurrencyChanged;

  const _LoadingScaffold({
    required this.url,
    required this.previewInfo,
    required this.scrapeState,
    required this.selectedLanguage,
    required this.selectedCurrency,
    required this.currencyOptions,
    required this.onLanguageChanged,
    required this.onCurrencyChanged,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        MenuSliverAppBar(
          restaurantUrl: url,
          previewInfo: previewInfo,
          restaurantInfo: null,
          selectedLanguage: selectedLanguage,
          selectedCurrency: selectedCurrency,
          currencyOptions: currencyOptions,
          onLanguageChanged: onLanguageChanged,
          onCurrencyChanged: onCurrencyChanged,
        ),
        SliverFillRemaining(
          child: switch (scrapeState) {
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
            ScrapeFailure(:final message) => Padding(
                padding: const EdgeInsets.all(24),
                child: ShadAlert.destructive(
                  title: const Text('Error'),
                  description: Text(message),
                ),
              ),
            ScrapeSuccess() => const SizedBox.shrink(),
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Success scaffold — SliverAppBar + sticky category tabs + tab content
// ---------------------------------------------------------------------------

class _SuccessScaffold extends StatefulWidget {
  final String url;
  final RestaurantPreviewInfo previewInfo;
  final ScrapeSuccess state;
  final String selectedLanguage;
  final String selectedCurrency;
  final List<String> currencyOptions;
  final ValueChanged<String> onLanguageChanged;
  final ValueChanged<String> onCurrencyChanged;

  const _SuccessScaffold({
    required this.url,
    required this.previewInfo,
    required this.state,
    required this.selectedLanguage,
    required this.selectedCurrency,
    required this.currencyOptions,
    required this.onLanguageChanged,
    required this.onCurrencyChanged,
  });

  @override
  State<_SuccessScaffold> createState() => _SuccessScaffoldState();
}

class _SuccessScaffoldState extends State<_SuccessScaffold> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<MenuCategory> get _categories => widget.state.categories;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
  }

  @override
  void didUpdateWidget(_SuccessScaffold old) {
    super.didUpdateWidget(old);
    if (old.state.categories.length != _categories.length) {
      _tabController.dispose();
      _tabController = TabController(length: _categories.length, vsync: this);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NestedScrollView(
      headerSliverBuilder: (context, innerBoxIsScrolled) => [
        MenuSliverAppBar(
          restaurantUrl: widget.url,
          previewInfo: widget.previewInfo,
          restaurantInfo: widget.state.restaurantInfo,
          selectedLanguage: widget.selectedLanguage,
          selectedCurrency: widget.selectedCurrency,
          currencyOptions: widget.currencyOptions,
          onLanguageChanged: widget.onLanguageChanged,
          onCurrencyChanged: widget.onCurrencyChanged,
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: CategoryTabsHeader(
            tabController: _tabController,
            categories: _categories,
          ),
        ),
      ],
      body: TabBarView(
        controller: _tabController,
        children: _categories.map((category) {
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: category.items.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
            itemBuilder: (context, index) => MenuItemCard(
              item: category.items[index],
              state: widget.state,
            ),
          );
        }).toList(),
      ),
    );
  }
}
