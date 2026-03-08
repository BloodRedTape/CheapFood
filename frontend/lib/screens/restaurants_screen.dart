import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../cubit/auth_cubit.dart';
import '../cubit/scrape_cubit.dart';
import 'menu_scrape_screen.dart';

class RestaurantsScreen extends StatefulWidget {
  const RestaurantsScreen({super.key});

  @override
  State<RestaurantsScreen> createState() => _RestaurantsScreenState();
}

class _RestaurantsScreenState extends State<RestaurantsScreen> {
  final _urlController = TextEditingController();
  final _cubits = <String, ScrapeCubit>{};

  ScrapeCubit _cubitFor(String url, String token) {
    return _cubits.putIfAbsent(url, () => ScrapeCubit(token: token)..scrape(url));
  }

  @override
  void dispose() {
    _urlController.dispose();
    for (final cubit in _cubits.values) {
      cubit.close();
    }
    super.dispose();
  }

  void _addUrl(BuildContext context) {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    context.read<AuthCubit>().addUrl(url);
    _urlController.clear();
  }

  void _removeUrl(BuildContext context, String url) {
    _cubits.remove(url)?.close();
    context.read<AuthCubit>().removeUrl(url);
  }

  void _openScrape(BuildContext context, String url, String token) {
    final cubit = _cubitFor(url, token);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BlocProvider.value(
          value: cubit,
          child: MenuScrapeScreen(restaurantUrl: url),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, state) {
          if (state is! AuthSuccess) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Restaurants', style: ShadTheme.of(context).textTheme.h2),
                    const Spacer(),
                    ShadButton.outline(
                      onPressed: () => context.read<AuthCubit>().logout(),
                      child: Text('Sign out (${state.login})'),
                    ),
                  ],
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
                  child: state.urls.isEmpty
                      ? Center(child: Text('No restaurants yet', style: ShadTheme.of(context).textTheme.muted))
                      : ListView.separated(
                          itemCount: state.urls.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (context, index) {
                            final url = state.urls[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(url, style: ShadTheme.of(context).textTheme.p),
                              onTap: () => _openScrape(context, url, state.token),
                              trailing: ShadButton.ghost(
                                onPressed: () => _removeUrl(context, url),
                                child: const Icon(Icons.delete_outline, size: 18),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
