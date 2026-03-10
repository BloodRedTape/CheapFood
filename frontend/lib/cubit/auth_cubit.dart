import 'dart:convert';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

sealed class AuthState {}

final class AuthInitial extends AuthState {}

final class AuthLoading extends AuthState {}

final class AuthSuccess extends AuthState {
  final String login;
  final String token;

  AuthSuccess({required this.login, required this.token});
}

final class AuthFailure extends AuthState {
  final String message;
  AuthFailure(this.message);
}

class AuthCubit extends Cubit<AuthState> {
  static const _keyToken = 'auth_token';

  AuthCubit() : super(AuthInitial()) {
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyToken);
    if (token == null) return;

    try {
      // Verify token is still valid by checking if we can parse it
      final parts = token.split('.');
      if (parts.length == 3) {
        final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
        ) as Map<String, dynamic>;
        final login = payload['login'] as String?;
        if (login != null) {
          emit(AuthSuccess(login: login, token: token));
          return;
        }
      }
    } catch (_) {}

    final prefs2 = await SharedPreferences.getInstance();
    await prefs2.remove(_keyToken);
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
  }

  Future<void> _clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
  }

  Future<void> login(String login, String password) async {
    emit(AuthLoading());
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'login': login, 'password': password}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        final token = data['token'] as String;
        await _saveToken(token);
        emit(AuthSuccess(login: data['login'] as String, token: token));
      } else {
        emit(AuthFailure(data['error'] as String? ?? 'Login failed'));
      }
    } catch (e) {
      emit(AuthFailure('Connection failed: $e'));
    }
  }

  Future<void> register(String login, String password) async {
    emit(AuthLoading());
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'login': login, 'password': password}),
      );
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200) {
        final token = data['token'] as String;
        await _saveToken(token);
        emit(AuthSuccess(login: data['login'] as String, token: token));
      } else {
        emit(AuthFailure(data['error'] as String? ?? 'Registration failed'));
      }
    } catch (e) {
      emit(AuthFailure('Connection failed: $e'));
    }
  }

  Future<void> logout() async {
    await _clearToken();
    emit(AuthInitial());
  }
}
