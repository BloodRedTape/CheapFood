import 'exchange_rates.dart';
import 'menu_category.dart';

class ScrapeResponse {
  final List<MenuCategory> categories;
  final ExchangeRates exchangeRates;

  const ScrapeResponse({required this.categories, required this.exchangeRates});

  factory ScrapeResponse.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'] as List<dynamic>;
    return ScrapeResponse(
      categories: rawCategories
          .map((e) => MenuCategory.fromJson(e as Map<String, dynamic>))
          .toList(),
      exchangeRates: ExchangeRates.fromJson(
          json['exchange_rates'] as Map<String, dynamic>),
    );
  }

  Map<String, dynamic> toJson() => {
        'categories': categories.map((e) => e.toJson()).toList(),
        'exchange_rates': exchangeRates.toJson(),
      };
}
