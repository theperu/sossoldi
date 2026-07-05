import 'base_entity.dart';

const String exchangeRateTable = 'exchange_rate';

class ExchangeRateFields extends BaseEntityFields {
  static String id = BaseEntityFields.getId;
  static String baseCurrency = 'baseCurrency';
  static String targetCurrency = 'targetCurrency';
  static String rate = 'rate';
  static String date = 'date';
  static String createdAt = BaseEntityFields.getCreatedAt;

  static final List<String> allFields = [
    BaseEntityFields.id,
    baseCurrency,
    targetCurrency,
    rate,
    date,
    createdAt,
  ];
}

class ExchangeRate extends BaseEntity {
  final String baseCurrency;
  final String targetCurrency;
  final double rate;
  final String date;

  const ExchangeRate({
    super.id,
    required this.baseCurrency,
    required this.targetCurrency,
    required this.rate,
    required this.date,
    super.createdAt,
  });

  ExchangeRate copy({
    int? id,
    String? baseCurrency,
    String? targetCurrency,
    double? rate,
    String? date,
    DateTime? createdAt,
  }) => ExchangeRate(
    id: id ?? this.id,
    baseCurrency: baseCurrency ?? this.baseCurrency,
    targetCurrency: targetCurrency ?? this.targetCurrency,
    rate: rate ?? this.rate,
    date: date ?? this.date,
    createdAt: createdAt ?? this.createdAt,
  );

  static ExchangeRate fromJson(Map<String, Object?> json) => ExchangeRate(
    id: json[BaseEntityFields.id] as int?,
    baseCurrency: json[ExchangeRateFields.baseCurrency] as String,
    targetCurrency: json[ExchangeRateFields.targetCurrency] as String,
    rate: (json[ExchangeRateFields.rate] as num).toDouble(),
    date: json[ExchangeRateFields.date] as String,
    createdAt: DateTime.parse(json[ExchangeRateFields.createdAt] as String),
  );

  Map<String, Object?> toJson() => {
    BaseEntityFields.id: id,
    ExchangeRateFields.baseCurrency: baseCurrency,
    ExchangeRateFields.targetCurrency: targetCurrency,
    ExchangeRateFields.rate: rate,
    ExchangeRateFields.date: date,
    ExchangeRateFields.createdAt:
        (createdAt ?? DateTime.now()).toIso8601String(),
  };
}
