const String scraperUrl = 'http://localhost:8000';
const int port = 8080;
const String exchangeRateApiUrl = 'https://api.exchangerate-api.com/v4/latest';
const Duration cacheTtl = Duration(hours: 1);
const String menuCacheDir = '.run_tree';
const Set<String> allowedCurrencies = {'USD', 'EUR', 'CZK', 'PLN', 'UAH'};
