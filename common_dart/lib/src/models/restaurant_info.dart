class DaySchedule {
  final int day; // 0=Sun, 1=Mon, ..., 6=Sat
  final String? open; // "HH:MM"
  final String? close; // "HH:MM"

  const DaySchedule({required this.day, this.open, this.close});

  factory DaySchedule.fromJson(Map<String, dynamic> json) => DaySchedule(
        day: json['day'] as int,
        open: json['open'] as String?,
        close: json['close'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'day': day,
        'open': open,
        'close': close,
      };
}

class RestaurantInfo {
  final String? name;
  final List<String> phones;
  final String? address;
  final List<DaySchedule> workingHours;
  final String? siteLanguage;

  const RestaurantInfo({
    this.name,
    this.phones = const [],
    this.address,
    this.workingHours = const [],
    this.siteLanguage,
  });

  factory RestaurantInfo.fromJson(Map<String, dynamic> json) => RestaurantInfo(
        name: json['name'] as String?,
        phones: (json['phones'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        address: json['address'] as String?,
        workingHours: (json['working_hours'] as List<dynamic>?)
                ?.map((e) => DaySchedule.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        siteLanguage: json['site_language'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'phones': phones,
        'address': address,
        'working_hours': workingHours.map((e) => e.toJson()).toList(),
        'site_language': siteLanguage,
      };
}
