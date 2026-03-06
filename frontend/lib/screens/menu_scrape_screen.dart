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
                  builder: (context, state) {
                    return ShadButton(
                      onPressed: state is ScrapeLoading
                          ? null
                          : () => _submit(context),
                      child: const Text('Найти'),
                    );
                  },
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
                      title: const Text('Ошибка'),
                      description: Text(message),
                    ),
                  ScrapeSuccess(:final items) => _MenuList(items: items),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuList extends StatelessWidget {
  final List<MenuItem> items;

  const _MenuList({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Найдено блюд: ${items.length}',
          style: ShadTheme.of(context).textTheme.muted,
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(),
            itemBuilder: (context, index) {
              final item = items[index];
              return ShadCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: ShadTheme.of(context).textTheme.p,
                          ),
                          if (item.description != null)
                            Text(
                              item.description!,
                              style: ShadTheme.of(context).textTheme.muted,
                            ),
                        ],
                      ),
                    ),
                    if (item.price != null)
                      Text(
                        '${item.price!.toStringAsFixed(2)} ${item.currency}',
                        style: ShadTheme.of(context)
                            .textTheme
                            .p
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
