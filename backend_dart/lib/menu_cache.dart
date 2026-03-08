import 'dart:convert';
import 'dart:io';

import 'package:common_dart/common_dart.dart';
import 'package:path/path.dart' as p;

import 'config.dart';

class MenuCache {
  final Directory _baseDir;

  MenuCache()
      : _baseDir = Directory(
          '${File(Platform.script.toFilePath()).parent.parent.path}/$menuCacheDir',
        ) {
    _baseDir.createSync(recursive: true);
  }

  /// Returns a subdirectory for the given URL, e.g. cache/www_example_com/
  /// All non-word characters (including slashes) are replaced with underscores
  /// to produce a flat, single-level name — no path separators, no traversal.
  Directory _dirFor(String url) {
    final name = url
        .replaceAll(RegExp(r'https?://'), '')
        .replaceAll(RegExp(r'[^\w]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .toLowerCase();
    final dirPath = p.join(_baseDir.path, name);
    if (!p.isWithin(_baseDir.path, dirPath)) {
      throw ArgumentError('Path traversal detected for url: $url');
    }
    return Directory(dirPath);
  }

  File _fileFor(String url, String name) {
    // Sanitize name (language code or 'original'): only word chars and hyphens.
    final safeName = name.replaceAll(RegExp(r'[^\w\-]'), '_');
    final dir = _dirFor(url);
    dir.createSync(recursive: true);
    final filePath = p.join(dir.path, '$safeName.json');
    if (!p.isWithin(_baseDir.path, filePath)) {
      throw ArgumentError('Path traversal detected for name: $name');
    }
    return File(filePath);
  }

  List<MenuCategory>? _readFile(File file) {
    if (!file.existsSync()) return null;
    print('Menu cache hit: ${file.path}');
    final raw = jsonDecode(file.readAsStringSync()) as List<dynamic>;
    return raw
        .map((e) => MenuCategory.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void _writeFile(File file, List<MenuCategory> categories) {
    file.writeAsStringSync(
        jsonEncode(categories.map((e) => e.toJson()).toList()));
    print('Menu cached: ${file.path}');
  }

  void clearUrl(String url) {
    final dir = _dirFor(url);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
      print('Menu cache cleared: ${dir.path}');
    }
  }

  List<MenuCategory>? readOriginal(String url) =>
      _readFile(_fileFor(url, 'original'));

  void writeOriginal(String url, List<MenuCategory> categories) =>
      _writeFile(_fileFor(url, 'original'), categories);

  List<MenuCategory>? readTranslated(String url, String language) =>
      _readFile(_fileFor(url, language));

  void writeTranslated(String url, String language, List<MenuCategory> categories) =>
      _writeFile(_fileFor(url, language), categories);
}
