class ExchangeRates {
  final String base;
  final Map<String, double> rates;

  const ExchangeRates({required this.base, required this.rates});

  factory ExchangeRates.fromJson(Map<String, dynamic> json) {
    final rawRates = json['rates'] as Map<String, dynamic>;
    return ExchangeRates(
      base: json['base'] as String,
      rates: rawRates.map((k, v) => MapEntry(k, (v as num).toDouble())),
    );
  }

  Map<String, dynamic> toJson() => {
        'base': base,
        'rates': rates,
      };
}
