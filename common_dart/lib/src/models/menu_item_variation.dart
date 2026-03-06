class MenuItemVariation {
  final double? price;
  final String currency;
  final String? unit;
  final double? unitSize;

  const MenuItemVariation({
    this.price,
    this.currency = 'USD',
    this.unit,
    this.unitSize,
  });

  factory MenuItemVariation.fromJson(Map<String, dynamic> json) {
    return MenuItemVariation(
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
        if (price != null) 'price': price,
        'currency': currency,
        if (unit != null) 'unit': unit,
        if (unitSize != null) 'unit_size': unitSize,
      };
}
