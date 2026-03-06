import 'exchange_rates.dart';
import 'menu_item.dart';

class ScrapeResponse {
  final List<MenuItem> items;
  final ExchangeRates exchangeRates;

  const ScrapeResponse({required this.items, required this.exchangeRates});

  factory ScrapeResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>;
    return ScrapeResponse(
      items: rawItems
          .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      exchangeRates: ExchangeRates.fromJson(
          json['exchange_rates'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'items': items.map((e) => e.toJson()).toList(),
        'exchange_rates': exchangeRates.toJson(),
      };
}
