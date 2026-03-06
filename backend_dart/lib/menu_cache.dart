import 'dart:convert';
import 'dart:io';

import 'package:common_dart/common_dart.dart';

import 'config.dart';

class MenuCache {
  final Directory _dir;

  MenuCache()
      : _dir = Directory(
          '${File(Platform.script.toFilePath()).parent.parent.path}/$menuCacheDir',
        ) {
    _dir.createSync(recursive: true);
  }

  String _fileNameFor(String url) {
    final sanitized = url
        .replaceAll(RegExp(r'https?://'), '')
        .replaceAll(RegExp(r'[^\w]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .toLowerCase();
    return '$sanitized.json';
  }

  File _fileFor(String url) => File('${_dir.path}/${_fileNameFor(url)}');

  List<MenuItem>? read(String url) {
    final file = _fileFor(url);
    if (!file.existsSync()) return null;
    print('Menu cache hit: ${file.path}');
    final raw = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    return raw.map((e) => MenuItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  void write(String url, List<MenuItem> items) {
    final file = _fileFor(url);
    file.writeAsStringSync(jsonEncode(items.map((e) => e.toJson()).toList()));
    print('Menu cached: ${file.path}');
  }
}
