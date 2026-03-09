import 'exchange_rates.dart';
import 'menu_category.dart';
import 'restaurant_info.dart';

class ScrapeResponse {
  final List<MenuCategory> categories;
  final ExchangeRates exchangeRates;
  final RestaurantInfo restaurantInfo;

  const ScrapeResponse({
    required this.categories,
    required this.exchangeRates,
    required this.restaurantInfo,
  });

  factory ScrapeResponse.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'] as List<dynamic>;
    return ScrapeResponse(
      categories: rawCategories
          .map((e) => MenuCategory.fromJson(e as Map<String, dynamic>))
          .toList(),
      exchangeRates: ExchangeRates.fromJson(
          json['exchange_rates'] as Map<String, dynamic>),
      restaurantInfo: json['restaurant_info'] != null
          ? RestaurantInfo.fromJson(
              json['restaurant_info'] as Map<String, dynamic>)
          : const RestaurantInfo(),
    );
  }

  Map<String, dynamic> toJson() => {
        'categories': categories.map((e) => e.toJson()).toList(),
        'exchange_rates': exchangeRates.toJson(),
        'restaurant_info': restaurantInfo.toJson(),
      };
}
