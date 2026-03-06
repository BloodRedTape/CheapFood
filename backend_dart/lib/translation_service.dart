import 'dart:convert';

import 'package:common_dart/common_dart.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

const String _openaiApiUrl = 'https://api.openai.com/v1/chat/completions';
const String _openaiModel = 'gpt-5-mini';

class TranslationService {
  /// Returns [categories] translated to [language] (BCP-47 tag, e.g. 'en', 'ru').
  /// Each category is translated in a separate parallel request.
  Future<List<MenuCategory>> translate({
    required String language,
    required List<MenuCategory> categories,
  }) async {
    final totalItems = categories.fold(0, (sum, c) => sum + c.items.length);
    print('Translating ${categories.length} categories ($totalItems items) to $language via OpenAI $_openaiModel (parallel)');
    return Future.wait(categories.map((c) => _translateCategory(c, language)));
  }

  Future<MenuCategory> _translateCategory(MenuCategory category, String language) async {
    // Build a flat list of non-null strings to translate, tracking their origin slots.
    // Each slot is (itemIndex, isDescription): itemIndex == -1 means category name.
    final strings = <String>[];
    final slots = <(int, bool)>[];

    if (category.name != null) {
      strings.add(category.name!);
      slots.add((-1, false));
    }
    for (var i = 0; i < category.items.length; i++) {
      final item = category.items[i];
      strings.add(item.name);
      slots.add((i, false));
      if (item.description != null) {
        strings.add(item.description!);
        slots.add((i, true));
      }
    }

    if (strings.isEmpty) return category;

    final prompt = '''
You are a menu translator. Translate the following JSON array of strings to the language with BCP-47 tag "$language".
Return ONLY a raw JSON array of the same length with translated strings. No extra text or code fences.

${jsonEncode(strings)}''';

    final body = jsonEncode({
      'model': _openaiModel,
      'temperature': 1.0,
      'messages': [
        {'role': 'user', 'content': prompt},
      ],
    });

    final response = await http.post(
      Uri.parse(_openaiApiUrl),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $openaiApiKey'},
      body: body,
    );

    if (response.statusCode != 200) {
      print('OpenAI error body: ${response.body}');
      throw Exception('OpenAI API error: ${response.statusCode}');
    }

    final responseJson = jsonDecode(response.body) as Map<String, dynamic>;

    final choices = responseJson['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw Exception('OpenAI returned no choices');
    }

    final choice = choices.first as Map<String, dynamic>;
    final finishReason = choice['finish_reason'] as String?;
    if (finishReason == 'length') {
      throw Exception('OpenAI hit token limit — category "${category.name}" too large (${category.items.length} items)');
    }

    final text = choice['message']['content'] as String;
    print('OpenAI raw content for "${category.name}": $text');

    final start = text.indexOf('[');
    final end = text.lastIndexOf(']');
    if (start == -1 || end == -1) throw Exception('No JSON array found in OpenAI response: $text');
    final translated = jsonDecode(text.substring(start, end + 1)) as List<dynamic>;

    if (translated.length != strings.length) {
      throw Exception('OpenAI returned ${translated.length} strings, expected ${strings.length} for category "${category.name}"');
    }

    // Reconstruct category from translated strings using slots.
    String? translatedCategoryName = category.name;
    final translatedNames = List<String>.from(category.items.map((i) => i.name));
    final translatedDescs = List<String?>.from(category.items.map((i) => i.description));

    for (var i = 0; i < slots.length; i++) {
      final (itemIndex, isDescription) = slots[i];
      final value = translated[i] as String? ?? strings[i];
      if (itemIndex == -1) {
        translatedCategoryName = value;
      } else if (isDescription) {
        translatedDescs[itemIndex] = value;
      } else {
        translatedNames[itemIndex] = value;
      }
    }

    final translatedItems = List.generate(category.items.length, (i) {
      final original = category.items[i];
      return MenuItem(
        name: translatedNames[i],
        description: translatedDescs[i],
        variations: original.variations,
      );
    });

    return MenuCategory(name: translatedCategoryName, items: translatedItems);
  }
}
