import 'package:sqflite/sqflite.dart';

import '../../../model/exchange_rate.dart';
import '../sossoldi_database.dart';

class ExchangeRateRepository {
  ExchangeRateRepository({required SossoldiDatabase database})
    : _sossoldiDB = database;

  final SossoldiDatabase _sossoldiDB;

  Future<void> upsert(ExchangeRate item) async {
    final db = await _sossoldiDB.database;
    await db.insert(
      exchangeRateTable,
      item.toJson(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertAll(List<ExchangeRate> items) async {
    final db = await _sossoldiDB.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final item in items) {
        batch.insert(
          exchangeRateTable,
          item.toJson(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<ExchangeRate?> getLatestRate({
    required String base,
    required String target,
  }) async {
    final db = await _sossoldiDB.database;
    final rows = await db.query(
      exchangeRateTable,
      where:
          '${ExchangeRateFields.baseCurrency} = ? AND ${ExchangeRateFields.targetCurrency} = ?',
      whereArgs: [base, target],
      orderBy: '${ExchangeRateFields.date} DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      return null;
    }

    return ExchangeRate.fromJson(rows.first);
  }

  Future<String?> getLatestRateDate({
    required String base,
    required String target,
  }) async {
    final row = await getLatestRate(base: base, target: target);
    return row?.date;
  }

  Future<String?> getMaxDate() async {
    final db = await _sossoldiDB.database;
    final rows = await db.rawQuery(
      'SELECT MAX(${ExchangeRateFields.date}) AS maxDate FROM $exchangeRateTable',
    );
    final value = rows.first['maxDate'];
    return value is String ? value : null;
  }
}
