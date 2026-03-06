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
  final List<String> urls;

  AuthSuccess({required this.login, required this.token, required this.urls});

  AuthSuccess withUrls(List<String> urls) => AuthSuccess(login: login, token: token, urls: urls);
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

  Map<String, String> _authHeaders(String token) => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_keyToken);
    if (token == null) return;

    try {
      final response = await http.get(
        Uri.parse('$backendUrl/restaurants'),
        headers: _authHeaders(token),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // Extract login from token payload (middle part, base64)
        final parts = token.split('.');
        if (parts.length == 3) {
          final payload = jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
          ) as Map<String, dynamic>;
          final login = payload['login'] as String?;
          if (login != null) {
            emit(AuthSuccess(login: login, token: token, urls: (data['urls'] as List).cast<String>()));
            return;
          }
        }
      }
    } catch (_) {}

    // Token invalid or expired — clear it
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
        emit(AuthSuccess(login: data['login'] as String, token: token, urls: (data['urls'] as List).cast<String>()));
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
        emit(AuthSuccess(login: data['login'] as String, token: token, urls: (data['urls'] as List).cast<String>()));
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

  Future<void> addUrl(String url) async {
    final current = state;
    if (current is! AuthSuccess) return;
    try {
      final response = await http.post(
        Uri.parse('$backendUrl/restaurants'),
        headers: _authHeaders(current.token),
        body: jsonEncode({'url': url}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        emit(current.withUrls((data['urls'] as List).cast<String>()));
      }
    } catch (_) {}
  }

  Future<void> removeUrl(String url) async {
    final current = state;
    if (current is! AuthSuccess) return;
    try {
      final request = http.Request('DELETE', Uri.parse('$backendUrl/restaurants'))
        ..headers.addAll(_authHeaders(current.token))
        ..body = jsonEncode({'url': url});
      final streamed = await http.Client().send(request);
      if (streamed.statusCode == 200) {
        final body = await streamed.stream.bytesToString();
        final data = jsonDecode(body) as Map<String, dynamic>;
        emit(current.withUrls((data['urls'] as List).cast<String>()));
      }
    } catch (_) {}
  }
}
