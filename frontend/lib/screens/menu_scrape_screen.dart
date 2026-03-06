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

class _MenuScrapeScreenState extends State<MenuScrapeScreen> {
  final TextEditingController _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _submit(BuildContext context) {
    context.read<ScrapeCubit>().scrape(_urlController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('CheapFood', style: ShadTheme.of(context).textTheme.h2),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ShadInput(
                    controller: _urlController,
                    placeholder: const Text('https://example.com/menu'),
                    onSubmitted: (_) => _submit(context),
                  ),
                ),
                const SizedBox(width: 12),
                BlocBuilder<ScrapeCubit, ScrapeState>(
                  buildWhen: (prev, curr) =>
                      (prev is ScrapeLoading) != (curr is ScrapeLoading),
                  builder: (context, state) => ShadButton(
                    onPressed: state is ScrapeLoading
                        ? null
                        : () => _submit(context),
                    child: const Text('Search'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: BlocBuilder<ScrapeCubit, ScrapeState>(
                builder: (context, state) => switch (state) {
                  ScrapeInitial() => const SizedBox.shrink(),
                  ScrapeLoading() =>
                    const Center(child: CircularProgressIndicator()),
                  ScrapeFailure(:final message) => ShadAlert.destructive(
                      title: const Text('Error'),
                      description: Text(message),
                    ),
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

class _SuccessView extends StatefulWidget {
  final ScrapeSuccess state;

  const _SuccessView({required this.state});

  @override
  State<_SuccessView> createState() => _SuccessViewState();
}

class _SuccessViewState extends State<_SuccessView> {
  late final List<String> _currencies;
  late final List<ShadOption<String>> _options;

  @override
  void initState() {
    super.initState();
    _currencies = ({
      widget.state.exchangeRates.base,
      ...widget.state.exchangeRates.rates.keys,
    }).toList()
      ..sort();
    _options = _currencies
        .map((c) => ShadOption(value: c, child: Text(c)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ScrapeCubit, ScrapeState>(
      builder: (context, state) {
        if (state is! ScrapeSuccess) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '${state.items.length} items found',
                  style: ShadTheme.of(context).textTheme.muted,
                ),
                const Spacer(),
                ShadSelect<String>(
                  initialValue: state.selectedCurrency,
                  onChanged: (value) {
                    if (value != null) {
                      context.read<ScrapeCubit>().selectCurrency(value);
                    }
                  },
                  options: _options,
                  selectedOptionBuilder: (context, value) => Text(value),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: state.items.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  final item = state.items[index];
                  return _MenuItemCard(
                    item: item,
                    convertedPrice: state.convertPrice(item.price, item.currency),
                    displayCurrency: state.selectedCurrency,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final double? convertedPrice;
  final String displayCurrency;

  const _MenuItemCard({
    required this.item,
    required this.convertedPrice,
    required this.displayCurrency,
  });

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: ShadTheme.of(context).textTheme.p),
                if (item.description != null)
                  Text(
                    item.description!,
                    style: ShadTheme.of(context).textTheme.muted,
                  ),
              ],
            ),
          ),
          if (convertedPrice != null)
            Text(
              '${convertedPrice!.toStringAsFixed(2)} $displayCurrency',
              style: ShadTheme.of(context)
                  .textTheme
                  .p
                  .copyWith(fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }
}
