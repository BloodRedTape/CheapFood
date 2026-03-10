import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../cubit/auth_cubit.dart';
import '../cubit/restaurants_cubit.dart';
import '../widgets/restaurant_card.dart';
import 'menu_scrape/menu_scrape_screen.dart';

class RestaurantsScreen extends StatefulWidget {
  const RestaurantsScreen({super.key});

  @override
  State<RestaurantsScreen> createState() => _RestaurantsScreenState();
}

class _RestaurantsScreenState extends State<RestaurantsScreen> {
  final _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  void _addUrl(BuildContext context) {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    context.read<RestaurantsCubit>().addUrl(url);
    _urlController.clear();
  }

  void _openScrape(BuildContext context, String url) {
    context.read<RestaurantsCubit>().scrape(url);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: context.read<RestaurantsCubit>(),
          child: MenuScrapeScreen(restaurantUrl: url),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BlocBuilder<AuthCubit, AuthState>(
              builder: (context, authState) => Row(
                children: [
                  Text('Restaurants', style: ShadTheme.of(context).textTheme.h2),
                  const Spacer(),
                  ShadButton.outline(
                    onPressed: () => context.read<AuthCubit>().logout(),
                    child: Text('Sign out (${authState is AuthSuccess ? authState.login : ''})'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: ShadInput(
                    controller: _urlController,
                    placeholder: const Text('https://example.com/menu'),
                    onSubmitted: (_) => _addUrl(context),
                  ),
                ),
                const SizedBox(width: 12),
                ShadButton(
                  onPressed: () => _addUrl(context),
                  child: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: BlocBuilder<RestaurantsCubit, RestaurantsState>(
                buildWhen: (prev, next) => prev.urls.join(',') != next.urls.join(','),
                builder: (context, state) {
                  if (state.entries.isEmpty) {
                    return Center(child: Text('No restaurants yet', style: ShadTheme.of(context).textTheme.muted));
                  }
                  return ListView.separated(
                    itemCount: state.entries.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final url = state.entries[index].info.url;
                      return RestaurantCard(
                        url: url,
                        onTap: () => _openScrape(context, url),
                        onDelete: () => context.read<RestaurantsCubit>().removeUrl(url),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
