class ApiConstants {
  ApiConstants._();

  /// Public HAFAS REST API (no auth needed, 100 req/min)
  static const hafasBaseUrl = 'https://v6.db.transport.rest';

  /// Deutsche Bahn internal web API (no auth needed)
  static const dbWebApiBaseUrl = 'https://www.bahn.de/web/api';

  /// DB international web API
  static const dbIntlApiBaseUrl = 'https://int.bahn.de/web/api';

  /// User-Agent mimicking a browser
  static const userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Mobile Safari/537.36';

  /// Default results per query
  static const defaultResults = 6;

  /// Rate limit delay between sequential API calls (ms)
  static const defaultDelayMs = 400;
}

class AppConstants {
  AppConstants._();

  static const appName = 'Bessere Bahn';
  static const appVersion = '2.0.0';

  /// Major German stations (EVA numbers) for train number lookup fallback
  static const majorStations = {
    'Berlin Hbf': '8011160',
    'Hamburg Hbf': '8002549',
    'München Hbf': '8000261',
    'Frankfurt(Main)Hbf': '8000105',
    'Köln Hbf': '8000207',
    'Stuttgart Hbf': '8000096',
    'Düsseldorf Hbf': '8000085',
    'Hannover Hbf': '8000152',
    'Mannheim Hbf': '8000244',
    'Nürnberg Hbf': '8000284',
  };
}
