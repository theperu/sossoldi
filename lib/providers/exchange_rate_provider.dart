import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../services/currency/exchange_rate_service.dart';
import '../services/database/repositories/currency_repository.dart';
import '../services/database/repositories/exchange_rate_repository.dart';
import '../services/database/sossoldi_database.dart';

part 'exchange_rate_provider.g.dart';

@Riverpod(keepAlive: true)
ExchangeRateService exchangeRateService(Ref ref) {
  return ExchangeRateService(
    exchangeRateRepository: ExchangeRateRepository(
      database: ref.watch(databaseProvider),
    ),
    currencyRepository: ref.watch(currencyRepositoryProvider),
  );
}

@riverpod
Future<String?> latestRateDate(Ref ref) async {
  return ref.watch(exchangeRateServiceProvider).latestRateDate();
}
