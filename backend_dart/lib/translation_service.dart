import 'dart:convert';

import 'package:common_dart/common_dart.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

const String _openaiApiUrl = 'https://api.openai.com/v1/chat/completions';
const String _openaiModel = 'gpt-5-mini';

class TranslationService {
  /// Returns [categories] translated to [language] (BCP-47 tag, e.g. 'en', 'ru').
  Future<List<MenuCategory>> translate({
    required String language,
    required List<MenuCategory> categories,
  }) async {
    // Flatten all items to translate in one batch
    final allItems = categories.expand((c) => c.items).toList();
    print('Translating ${allItems.length} items to $language via OpenAI $_openaiModel');
    final translatedItems = await _callOpenAI(items: allItems, language: language);

    // Rebuild categories with translated items
    int offset = 0;
    return categories.map((c) {
      final slice = translatedItems.sublist(offset, offset + c.items.length);
      offset += c.items.length;
      return MenuCategory(name: c.name, items: slice);
    }).toList();
  }

  Future<List<MenuItem>> _callOpenAI({required List<MenuItem> items, required String language}) async {
    // Build compact input: only name + description need translation.
    final input = items.map((i) => {'name': i.name, if (i.description != null) 'description': i.description}).toList();

    final prompt = '''
You are a menu translator. Translate the following menu items to the language with BCP-47 tag "$language".
Return ONLY a raw JSON array (starting with "[") with the same number of objects, each having "name" and optionally "description" (only if the original has a description).
Do not wrap it in an object. Do not add any extra text, markdown, or code fences.

Input JSON:
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
      throw Exception('OpenAI hit token limit — batch too large (${items.length} items)');
    }

    final text = choice['message']['content'] as String;

    print('OpenAI raw content: $text');
    dynamic parsed = jsonDecode(text);
    List<dynamic> translated;
    if (parsed is List) {
      translated = parsed;
    } else if (parsed is Map) {
      final listValue = parsed.values.whereType<List>().firstOrNull;
      if (listValue != null) {
        translated = listValue;
      } else {
        throw Exception('OpenAI response Map has no List value: $parsed');
      }
    } else {
      throw Exception('Unexpected OpenAI response shape: $parsed');
    }

    if (translated.length != items.length) {
      throw Exception('OpenAI returned ${translated.length} items, expected ${items.length}');
    }

    return List.generate(items.length, (i) {
      final t = translated[i] as Map<String, dynamic>;
      final original = items[i];
      return MenuItem(
        name: (t['name'] as String?) ?? original.name,
        description: (t['description'] as String?) ?? original.description,
        price: original.price,
        currency: original.currency,
      );
    });
  }
}
