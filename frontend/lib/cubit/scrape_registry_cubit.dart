import 'package:flutter_bloc/flutter_bloc.dart';

import 'scrape_cubit.dart';

/// Holds all [ScrapeCubit]s keyed by URL. Lives at the app level.
class ScrapeRegistryCubit extends Cubit<void> {
  ScrapeRegistryCubit() : super(null);

  final _cubits = <String, ScrapeCubit>{};

  ScrapeCubit get(String url, String token) =>
      _cubits.putIfAbsent(url, () => ScrapeCubit(token: token));

  ScrapeCubit? find(String url) => _cubits[url];

  void remove(String url) => _cubits.remove(url)?.close();

  @override
  Future<void> close() {
    for (final cubit in _cubits.values) {
      cubit.close();
    }
    return super.close();
  }
}
