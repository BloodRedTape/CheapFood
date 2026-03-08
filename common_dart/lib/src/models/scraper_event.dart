import 'dart:convert';

import 'menu_category.dart';
import 'scrape_response.dart';

sealed class ScraperEvent {
  const ScraperEvent();

  List<int> toSse();

  static ScraperEvent? fromSse(String type, String data) => switch (type) {
        'progress' => ScraperProgressEvent(data),
        'error' => ScraperErrorEvent(data),
        'result' => ScraperResultEvent(
            (jsonDecode(data) as List<dynamic>)
                .map((e) => MenuCategory.fromJson(e as Map<String, dynamic>))
                .toList(),
          ),
        'saturated_result' => ScraperSaturatedResultEvent(
            ScrapeResponse.fromJson(jsonDecode(data) as Map<String, dynamic>),
          ),
        _ => null,
      };

  static Stream<ScraperEvent> parseStream(Stream<List<int>> bytes) async* {
    String buffer = '';
    String? eventType;
    String? eventData;

    await for (final chunk in bytes) {
      buffer += utf8.decode(chunk);
      final lines = buffer.split('\n');
      buffer = lines.last;

      for (final line in lines.sublist(0, lines.length - 1)) {
        if (line.startsWith('event: ')) {
          eventType = line.substring(7).trim();
        } else if (line.startsWith('data: ')) {
          eventData = line.substring(6).trim();
        } else if (line.isEmpty && eventType != null && eventData != null) {
          final event = ScraperEvent.fromSse(eventType, eventData);
          if (event != null) yield event;
          eventType = null;
          eventData = null;
        }
      }
    }
  }
}

class ScraperProgressEvent extends ScraperEvent {
  final String message;
  const ScraperProgressEvent(this.message);

  @override
  List<int> toSse() => utf8.encode('event: progress\ndata: $message\n\n');
}

class ScraperErrorEvent extends ScraperEvent {
  final String message;
  const ScraperErrorEvent(this.message);

  @override
  List<int> toSse() => utf8.encode('event: error\ndata: $message\n\n');
}

/// Raw result from the Python scraper — categories only, no exchange rates.
class ScraperResultEvent extends ScraperEvent {
  final List<MenuCategory> categories;
  const ScraperResultEvent(this.categories);

  @override
  List<int> toSse() => utf8.encode(
      'event: result\ndata: ${jsonEncode(categories.map((c) => c.toJson()).toList())}\n\n');
}

/// Enriched result from backend to frontend — categories + exchange rates.
class ScraperSaturatedResultEvent extends ScraperEvent {
  final ScrapeResponse response;
  const ScraperSaturatedResultEvent(this.response);

  @override
  List<int> toSse() =>
      utf8.encode('event: saturated_result\ndata: ${jsonEncode(response.toJson())}\n\n');
}
