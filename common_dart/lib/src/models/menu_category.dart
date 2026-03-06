import 'menu_item.dart';

class MenuCategory {
  final String? name;
  final List<MenuItem> items;

  const MenuCategory({this.name, this.items = const []});

  factory MenuCategory.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return MenuCategory(
      name: json['name'] as String?,
      items: rawItems
          .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'items': items.map((e) => e.toJson()).toList(),
      };
}
