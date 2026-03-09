class RestaurantInfo {
  final String? name;
  final String? workingHours;
  final String? siteLanguage;

  const RestaurantInfo({this.name, this.workingHours, this.siteLanguage});

  factory RestaurantInfo.fromJson(Map<String, dynamic> json) => RestaurantInfo(
        name: json['name'] as String?,
        workingHours: json['working_hours'] as String?,
        siteLanguage: json['site_language'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'working_hours': workingHours,
        'site_language': siteLanguage,
      };
}
