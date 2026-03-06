import 'dart:convert';

import 'package:common_dart/common_dart.dart';
import 'package:http/http.dart' as http;

import 'config.dart';

const String _geminiApiUrl =
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

class TranslationService {
  /// Returns [items] translated to [language] (BCP-47 tag, e.g. 'en', 'ru').
  Future<List<MenuItem>> translate({
    required String language,
    required List<MenuItem> items,
  }) async {
    print('Translating ${items.length} items to $language via Gemini');
    return _callGemini(items: items, language: language);
  }

  Future<List<MenuItem>> _callGemini({
    required List<MenuItem> items,
    required String language,
  }) async {
    // Build compact input: only name + description need translation.
    final input = items
        .map((i) => {
              'name': i.name,
              if (i.description != null) 'description': i.description,
            })
        .toList();

    final prompt = '''
You are a menu translator. Translate the following menu items to the language with BCP-47 tag "$language".
Return ONLY a valid JSON array with the same number of objects, each having "name" and optionally "description" (only if the original has a description).
Do not add any extra text, markdown, or code fences.

Input JSON:
${jsonEncode(input)}
''';

    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'responseMimeType': 'application/json',
      },
    });

    final response = await http.post(
      Uri.parse('$_geminiApiUrl?key=$geminiApiKey'),
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

    if (response.statusCode != 200) {
      print('Gemini error body: ${response.body}');
      throw Exception('Gemini API error: ${response.statusCode}');
    }

    final responseJson = jsonDecode(response.body) as Map<String, dynamic>;

    // Check for content filter / safety block
    final candidates = responseJson['candidates'] as List?;
    if (candidates == null || candidates.isEmpty) {
      final feedback = responseJson['promptFeedback'];
      throw Exception('Gemini returned no candidates. Feedback: $feedback');
    }

    final candidate = candidates.first as Map<String, dynamic>;
    final finishReason = candidate['finishReason'] as String?;
    if (finishReason == 'MAX_TOKENS') {
      throw Exception('Gemini hit MAX_TOKENS — batch too large (${items.length} items)');
    }

    final text =
        ((candidate['content']['parts'] as List).first['text']) as String;

    final translated = jsonDecode(text) as List<dynamic>;

    if (translated.length != items.length) {
      throw Exception(
          'Gemini returned ${translated.length} items, expected ${items.length}');
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
