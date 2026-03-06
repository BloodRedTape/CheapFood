class MenuItem {
  final String name;
  final String? description;
  final double? price;
  final String currency;
  final String? unit;
  final double? unitSize;

  const MenuItem({
    required this.name,
    this.description,
    this.price,
    this.currency = 'USD',
    this.unit,
    this.unitSize,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    return MenuItem(
      name: json['name'] as String,
      description: json['description'] as String?,
      price: switch (json['price']) {
        num n => n.toDouble(),
        String s => double.tryParse(s),
        _ => null,
      },
      currency: (json['currency'] as String?) ?? 'USD',
      unit: json['unit'] as String?,
      unitSize: switch (json['unit_size']) {
        num n => n.toDouble(),
        String s => double.tryParse(s),
        _ => null,
      },
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        if (price != null) 'price': price,
        'currency': currency,
        if (unit != null) 'unit': unit,
        if (unitSize != null) 'unit_size': unitSize,
      };
}
