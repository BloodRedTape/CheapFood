import 'dart:convert';
import 'dart:io';

import 'package:common_dart/common_dart.dart';

import 'config.dart';

class MenuCache {
  final Directory _baseDir;

  MenuCache()
      : _baseDir = Directory(
          '${File(Platform.script.toFilePath()).parent.parent.path}/$menuCacheDir',
        ) {
    _baseDir.createSync(recursive: true);
  }

  /// Returns a subdirectory for the given URL, e.g. cache/www_example_com/menu/
  Directory _dirFor(String url) {
    final path = url
        .replaceAll(RegExp(r'https?://'), '')
        .replaceAll(RegExp(r'[^\w/]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'/+'), '/')
        .toLowerCase()
        .replaceAll('/', Platform.pathSeparator);
    return Directory('${_baseDir.path}${Platform.pathSeparator}$path');
  }

  File _fileFor(String url, String name) {
    final dir = _dirFor(url);
    dir.createSync(recursive: true);
    return File('${dir.path}${Platform.pathSeparator}$name.json');
  }

  List<MenuItem>? _readFile(File file) {
    if (!file.existsSync()) return null;
    print('Menu cache hit: ${file.path}');
    final raw = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    return raw.map((e) => MenuItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  void _writeFile(File file, List<MenuItem> items) {
    file.writeAsStringSync(jsonEncode(items.map((e) => e.toJson()).toList()));
    print('Menu cached: ${file.path}');
  }

  List<MenuItem>? readOriginal(String url) =>
      _readFile(_fileFor(url, 'original'));

  void writeOriginal(String url, List<MenuItem> items) =>
      _writeFile(_fileFor(url, 'original'), items);

  List<MenuItem>? readTranslated(String url, String language) =>
      _readFile(_fileFor(url, language));

  void writeTranslated(String url, String language, List<MenuItem> items) =>
      _writeFile(_fileFor(url, language), items);
}
