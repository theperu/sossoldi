// ignore_for_file: file_names

import 'package:sqflite/sqflite.dart';

import '../../../model/bank_account.dart';
import '../../../model/currency.dart';
import '../../../model/exchange_rate.dart';
import '../../../model/transaction.dart';
import '../migration_base.dart';

class MultiCurrencyMigration extends Migration {
  MultiCurrencyMigration()
    : super(version: 8, description: 'Add multi-currency support schema');

  Future<bool> _columnExists(Database db, String table, String column) async {
    final columns = await db.rawQuery('PRAGMA table_info(`$table`)');
    return columns.any((c) => c['name'] == column);
  }

  Future<void> _addColumnIfMissing(
    Database db, {
    required String table,
    required String column,
    required String definition,
  }) async {
    if (!await _columnExists(db, table, column)) {
      await db.execute('ALTER TABLE `$table` ADD COLUMN $column $definition');
    }
  }

  @override
  Future<void> up(Database db) async {
    await _addColumnIfMissing(
      db,
      table: bankAccountTable,
      column: BankAccountFields.currency,
      definition: 'TEXT NOT NULL DEFAULT "EUR"',
    );

    await _addColumnIfMissing(
      db,
      table: bankAccountTable,
      column: BankAccountFields.startingValueInMainCurrency,
      definition: 'REAL NOT NULL DEFAULT 0',
    );

    await db.execute(
      'UPDATE `$bankAccountTable` SET ${BankAccountFields.startingValueInMainCurrency} = ${BankAccountFields.startingValue}',
    );

    await _addColumnIfMissing(
      db,
      table: transactionTable,
      column: TransactionFields.currency,
      definition: 'TEXT',
    );

    await _addColumnIfMissing(
      db,
      table: transactionTable,
      column: TransactionFields.amountInMainCurrency,
      definition: 'REAL',
    );

    await _addColumnIfMissing(
      db,
      table: transactionTable,
      column: TransactionFields.transferDestinationAmount,
      definition: 'REAL',
    );

    await _addColumnIfMissing(
      db,
      table: transactionTable,
      column: TransactionFields.transferEffectiveRate,
      definition: 'REAL',
    );

    if (await _columnExists(
      db,
      transactionTable,
      TransactionFields.amountInMainCurrency,
    )) {
      await db.execute(
        'UPDATE `$transactionTable` SET ${TransactionFields.amountInMainCurrency} = ${TransactionFields.amount}',
      );
    }

    await db.execute('DELETE FROM $currencyTable');
    await db.execute('''
      INSERT INTO $currencyTable(${CurrencyFields.symbol}, ${CurrencyFields.code}, ${CurrencyFields.name}, ${CurrencyFields.mainCurrency}) VALUES
        ('€', 'EUR', 'Euro', 1),
        ('\$', 'USD', 'United States Dollar', 0),
        ('£', 'GBP', 'British Pound Sterling', 0),
        ('CHF', 'CHF', 'Swiss Franc', 0),
        ('\$', 'CAD', 'Canadian Dollar', 0),
        ('\$', 'AUD', 'Australian Dollar', 0),
        ('\$', 'NZD', 'New Zealand Dollar', 0),
        ('kr', 'SEK', 'Swedish Krona', 0),
        ('kr', 'NOK', 'Norwegian Krone', 0),
        ('kr', 'DKK', 'Danish Krone', 0),
        ('zł', 'PLN', 'Polish Zloty', 0),
        ('Kč', 'CZK', 'Czech Koruna', 0),
        ('Ft', 'HUF', 'Hungarian Forint', 0),
        ('R\$', 'BRL', 'Brazilian Real', 0),
        ('\$', 'MXN', 'Mexican Peso', 0),
        ('¥', 'JPY', 'Japanese Yen', 0),
        ('元', 'CNY', 'Chinese Renminbi', 0),
        ('\$', 'HKD', 'Hong Kong Dollar', 0),
        ('\$', 'SGD', 'Singapore Dollar', 0),
        ('₹', 'INR', 'Indian Rupee', 0),
        ('₩', 'KRW', 'South Korean Won', 0)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS $exchangeRateTable(
        ${ExchangeRateFields.id} INTEGER PRIMARY KEY AUTOINCREMENT,
        ${ExchangeRateFields.baseCurrency} TEXT NOT NULL,
        ${ExchangeRateFields.targetCurrency} TEXT NOT NULL,
        ${ExchangeRateFields.rate} REAL NOT NULL,
        ${ExchangeRateFields.date} TEXT NOT NULL,
        ${ExchangeRateFields.createdAt} TEXT NOT NULL,
        UNIQUE(${ExchangeRateFields.baseCurrency}, ${ExchangeRateFields.targetCurrency}, ${ExchangeRateFields.date})
      )
    ''');
  }
}