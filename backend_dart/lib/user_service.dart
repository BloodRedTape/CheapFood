import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import 'config.dart';

class User {
  final String login;
  final String passwordHash;
  final List<String> urls;

  const User({required this.login, required this.passwordHash, required this.urls});

  factory User.fromJson(Map<String, dynamic> json) => User(
    login: json['login'] as String,
    passwordHash: json['password_hash'] as String,
    urls: (json['urls'] as List<dynamic>).cast<String>(),
  );

  Map<String, dynamic> toJson() => {
    'login': login,
    'password_hash': passwordHash,
    'urls': urls,
  };

  User copyWith({List<String>? urls}) => User(
    login: login,
    passwordHash: passwordHash,
    urls: urls ?? this.urls,
  );
}

class UserService {
  final String _filePath;
  List<User> _users = [];

  UserService({String filePath = 'users.json'}) : _filePath = filePath {
    _load();
  }

  static String hashPassword(String password) =>
      sha256.convert(utf8.encode(password)).toString();

  String issueToken(String login) {
    final jwt = JWT({'login': login});
    return jwt.sign(SecretKey(jwtSecret), expiresIn: const Duration(days: 30));
  }

  /// Returns login if token is valid, null otherwise.
  String? verifyToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(jwtSecret));
      return (jwt.payload as Map<String, dynamic>)['login'] as String?;
    } catch (_) {
      return null;
    }
  }

  void _load() {
    final file = File(_filePath);
    if (!file.existsSync()) {
      _users = [];
      return;
    }
    final list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    _users = list.map((e) => User.fromJson(e as Map<String, dynamic>)).toList();
  }

  void _save() {
    File(_filePath).writeAsStringSync(jsonEncode(_users.map((u) => u.toJson()).toList()));
  }

  /// Returns null if login already taken.
  User? register(String login, String password) {
    if (_users.any((u) => u.login == login)) return null;
    final user = User(login: login, passwordHash: hashPassword(password), urls: []);
    _users.add(user);
    _save();
    return user;
  }

  /// Returns null if credentials are invalid.
  User? authenticate(String login, String password) {
    final hash = hashPassword(password);
    try {
      return _users.firstWhere((u) => u.login == login && u.passwordHash == hash);
    } catch (_) {
      return null;
    }
  }

  User? getUser(String login) {
    try {
      return _users.firstWhere((u) => u.login == login);
    } catch (_) {
      return null;
    }
  }

  /// Returns updated user, or null if user not found.
  User? addUrl(String login, String url) {
    final index = _users.indexWhere((u) => u.login == login);
    if (index == -1) return null;
    final user = _users[index];
    if (user.urls.contains(url)) return user;
    final updated = user.copyWith(urls: [...user.urls, url]);
    _users[index] = updated;
    _save();
    return updated;
  }

  /// Returns updated user, or null if user not found.
  User? removeUrl(String login, String url) {
    final index = _users.indexWhere((u) => u.login == login);
    if (index == -1) return null;
    final updated = _users[index].copyWith(
      urls: _users[index].urls.where((u) => u != url).toList(),
    );
    _users[index] = updated;
    _save();
    return updated;
  }
}
