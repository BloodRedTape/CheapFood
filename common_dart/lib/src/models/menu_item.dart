class MenuItem {
  final String name;
  final String? description;
  final double? price;
  final String currency;

  const MenuItem({
    required this.name,
    this.description,
    this.price,
    this.currency = 'USD',
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      name: json['name'] as String,
      description: json['description'] as String?,
      price: (json['price'] as num?)?.toDouble(),
      currency: (json['currency'] as String?) ?? 'USD',
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (price != null) 'price': price,
        'currency': currency,
      };
}
