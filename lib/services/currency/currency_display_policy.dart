class CurrencyDisplayPolicy {
  const CurrencyDisplayPolicy._();

  /// Single source of truth for currency display tokens.
  /// Dollar variants use regional prefixes (C$, A$, etc.) and
  /// kr-family currencies keep the shared "kr" symbol — both are
  /// the same convention used by Revolut/Wise.
  static const Map<String, String> symbolsByCode = {
    'EUR': '€',
    'USD': r'$',
    'GBP': '£',
    'CHF': 'CHF',
    'CAD': r'C$',
    'AUD': r'A$',
    'NZD': r'NZ$',
    'SEK': 'kr',
    'NOK': 'kr',
    'DKK': 'kr',
    'PLN': 'zł',
    'CZK': 'Kč',
    'HUF': 'Ft',
    'BRL': r'R$',
    'MXN': r'MX$',
    'JPY': '¥',
    'CNY': '元',
    'HKD': r'HK$',
    'SGD': r'S$',
    'INR': '₹',
    'KRW': '₩',
  };

  static String displayTokenForCode(String? code) {
    if (code == null || code.isEmpty) {
      return symbolsByCode['EUR']!;
    }
    return symbolsByCode[code] ?? code;
  }
}
