import 'dart:convert';

import 'package:common_dart/common_dart.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

sealed class ScrapeState {}

final class ScrapeInitial extends ScrapeState {}

final class ScrapeLoading extends ScrapeState {}

final class ScrapeSuccess extends ScrapeState {
  final List<MenuItem> items;
  ScrapeSuccess(this.items);
}

final class ScrapeFailure extends ScrapeState {
  final String message;
  ScrapeFailure(this.message);
}

class ScrapeCubit extends Cubit<ScrapeState> {
  static const String _backendUrl = 'http://localhost:8080';

  ScrapeCubit() : super(ScrapeInitial());

  Future<void> scrape(String url) async {
    if (url.trim().isEmpty) return;

    emit(ScrapeLoading());

    try {
      final request = ScrapeRequest(url: url.trim());
      final response = await http.post(
        Uri.parse('$_backendUrl/scrape'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(request.toJson()),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        final items = data
            .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
            .toList();
        emit(ScrapeSuccess(items));
      } else {
        emit(ScrapeFailure('Ошибка сервера: ${response.statusCode}'));
      }
    } catch (e) {
      emit(ScrapeFailure('Не удалось подключиться: $e'));
    }
  }
}
