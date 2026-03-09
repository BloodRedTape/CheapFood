class RestaurantPreviewInfo {
  final String url;
  final String? name;
  final int totalItems;
  final int itemsWithPrice;

  const RestaurantPreviewInfo({
    required this.url,
    this.name,
    required this.totalItems,
    required this.itemsWithPrice,
  });

  factory RestaurantPreviewInfo.fromJson(Map<String, dynamic> json) => RestaurantPreviewInfo(
        url: json['url'] as String,
        name: json['name'] as String?,
        totalItems: json['total_items'] as int,
        itemsWithPrice: json['items_with_price'] as int,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'name': name,
        'total_items': totalItems,
        'items_with_price': itemsWithPrice,
      };
}
