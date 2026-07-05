import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../model/bank_account.dart';
import '../model/currency.dart';
import '../model/transaction.dart';
import '../services/database/repositories/account_repository.dart';
import '../services/database/repositories/currency_repository.dart';
import '../services/database/repositories/transactions_repository.dart';
import '../services/database/sossoldi_database.dart';
import 'exchange_rate_provider.dart';

part 'currency_provider.g.dart';

@Riverpod(keepAlive: true)
class CurrencyState extends _$CurrencyState {
  //Initial currency selected (fallback)
  final Currency _defaultCurrency = const Currency(
    id: 1,
    symbol: '€',
    code: 'EUR',
    name: "Euro",
    mainCurrency: true,
  );

  @override
  Currency build() {
    _initializeState();
    return _defaultCurrency;
  }

  Future<void> _initializeState() async {
    final currency = await ref
        .read(currencyRepositoryProvider)
        .getSelectedCurrency();
    state = currency;
  }

  Future<void> setSelectedCurrency(Currency currency) async {
    final previousMainCurrency = state;
    final exchangeService = ref.read(exchangeRateServiceProvider);
    final db = await ref.read(databaseProvider).database;

    final accounts = await ref.read(accountRepositoryProvider).selectAll();
    final transactions = await ref.read(transactionsRepositoryProvider).selectAll();

    // Collect unique source currencies that need conversion (excluding the new main).
    final currencyCodes = <String>{
      for (final a in accounts) a.currency,
      for (final t in transactions) t.currency ?? previousMainCurrency.code,
    }..remove(currency.code);

    // Pre-fetch each rate exactly once — throws if any rate is missing.
    // No try/catch: a missing rate aborts the whole operation before any writes.
    final rates = <String, double>{};
    for (final code in currencyCodes) {
      rates[code] = await exchangeService.getRate(from: code, to: currency.code);
    }

    // All writes in one atomic transaction — either everything succeeds or nothing changes.
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE $currencyTable SET ${CurrencyFields.mainCurrency} = 0',
      );
      await txn.rawUpdate(
        'UPDATE $currencyTable SET ${CurrencyFields.mainCurrency} = 1'
        ' WHERE ${CurrencyFields.id} = ?',
        [currency.id],
      );

      for (final account in accounts) {
        final rate = rates[account.currency] ?? 1.0;
        await txn.rawUpdate(
          'UPDATE $bankAccountTable'
          ' SET ${BankAccountFields.startingValueInMainCurrency} = ?'
          ' WHERE ${BankAccountFields.id} = ?',
          [account.startingValue.toDouble() * rate, account.id],
        );
      }

      for (final transaction in transactions) {
        final code = transaction.currency ?? previousMainCurrency.code;
        final rate = rates[code] ?? 1.0;
        await txn.rawUpdate(
          'UPDATE $transactionTable'
          ' SET ${TransactionFields.currency} = ?,'
          ' ${TransactionFields.amountInMainCurrency} = ?'
          ' WHERE ${TransactionFields.id} = ?',
          [code, transaction.amount.toDouble() * rate, transaction.id],
        );
      }
    });

    state = currency;
  }
}
