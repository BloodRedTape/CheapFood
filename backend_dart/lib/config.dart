import 'dart:io';

import 'package:common_dart/common_dart.dart';

const String scraperUrl = 'http://localhost:8000';
const int port = 8080;
const String exchangeRateApiUrl = 'https://api.exchangerate-api.com/v4/latest';
const Duration cacheTtl = Duration(hours: 1);
const String menuCacheDir = '.run_tree';
const Set<String> allowedCurrencies = supportedCurrencies;

final Map<String, String> _env = {};

/// Reads bin/.env and merges into [_env]. Call once at startup.
void loadDotEnv() {
  final envFile = File(
    '${File(Platform.script.toFilePath()).parent.path}/.env',
  );
  if (!envFile.existsSync()) {
    print('.env not found at ${envFile.path}, relying on system environment');
    return;
  }
  for (final line in envFile.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final idx = trimmed.indexOf('=');
    if (idx < 1) continue;
    _env[trimmed.substring(0, idx).trim()] = trimmed.substring(idx + 1).trim();
  }
  print('.env loaded from ${envFile.path}');
}

String _getEnv(String key) =>
    _env[key] ?? Platform.environment[key] ?? '';

String get openaiApiKey {
  final key = _getEnv('OPENAI_API_KEY');
  if (key.isEmpty) throw StateError('OPENAI_API_KEY is not set');
  return key;
}
