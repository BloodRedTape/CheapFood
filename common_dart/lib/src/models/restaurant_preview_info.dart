class RestaurantPreviewInfo {
  final String url;
  final String? name;
  final int totalItems;
  final int itemsWithPrice;
  final String? iconUrl;

  const RestaurantPreviewInfo({
    required this.url,
    this.name,
    required this.totalItems,
    required this.itemsWithPrice,
    this.iconUrl,
  });

  factory RestaurantPreviewInfo.fromJson(Map<String, dynamic> json) => RestaurantPreviewInfo(
        url: json['url'] as String,
        name: json['name'] as String?,
        totalItems: json['total_items'] as int,
        itemsWithPrice: json['items_with_price'] as int,
        iconUrl: json['icon_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'url': url,
        'name': name,
        'total_items': totalItems,
        'items_with_price': itemsWithPrice,
        'icon_url': iconUrl,
      };
}
