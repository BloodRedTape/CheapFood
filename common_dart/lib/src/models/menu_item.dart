import 'menu_item_variation.dart';

class MenuItem {
  final String name;
  final String? description;
  final List<MenuItemVariation> variations;

  const MenuItem({
    required this.name,
    this.description,
    this.variations = const [],
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    final rawVariations = json['variations'] as List<dynamic>? ?? [];
    return MenuItem(
      name: json['name'] as String,
      description: json['description'] as String?,
      variations: rawVariations
          .map((e) => MenuItemVariation.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (description != null) 'description': description,
        'variations': variations.map((v) => v.toJson()).toList(),
      };
}
