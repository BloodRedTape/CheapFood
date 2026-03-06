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
    // Compact format: [categoryName, [[name, description|null], ...]]
    // null categoryName if absent.
    final inputItems = category.items.map((i) => [i.name, i.description]).toList();
    final input = [category.name, inputItems];

    final prompt = '''
You are a menu translator. Translate the following menu category to the language with BCP-47 tag "$language".
Input is a JSON array: [categoryName, [[name, description], ...]] where categoryName or description may be null.
Return ONLY a raw JSON array in the same format with translated strings. Keep null values as null. No extra text or code fences.

Input:
${jsonEncode(input)}
''';

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
    final parsed = jsonDecode(text.substring(start, end + 1)) as List<dynamic>;
    final translatedName = parsed[0] as String? ?? category.name;
    final rawItems = parsed[1] as List<dynamic>;

    if (rawItems.length != category.items.length) {
      throw Exception('OpenAI returned ${rawItems.length} items, expected ${category.items.length} for category "${category.name}"');
    }

    final translatedItems = List.generate(category.items.length, (i) {
      final t = rawItems[i] as List<dynamic>;
      final original = category.items[i];
      return MenuItem(
        name: (t[0] as String?) ?? original.name,
        description: (t[1] as String?) ?? original.description,
        price: original.price,
        currency: original.currency,
      );
    });

    return MenuCategory(name: translatedName, items: translatedItems);
  }
}
