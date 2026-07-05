import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../model/currency.dart';
import '../sossoldi_database.dart';

part 'currency_repository.g.dart';

@riverpod
CurrencyRepository currencyRepository(Ref ref) {
  return CurrencyRepository(database: ref.watch(databaseProvider));
}

class CurrencyRepository {
  CurrencyRepository({required SossoldiDatabase database})
    : _sossoldiDB = database;

  final SossoldiDatabase _sossoldiDB;

  Future<Currency> getSelectedCurrency() async {
    final db = await _sossoldiDB.database;

    final maps = await db.query(
      currencyTable,
      columns: CurrencyFields.allFields,
      where: '${CurrencyFields.mainCurrency} = ?',
      whereArgs: [1],
    );

    if (maps.isNotEmpty) {
      return Currency.fromJson(maps.first);
    } else {
      //fallback
      return const Currency(
        id: 1,
        symbol: '€',
        code: 'EUR',
        name: "Euro",
        mainCurrency: true,
      );
    }
  }

  Future<Currency> insert(Currency item) async {
    final db = await _sossoldiDB.database;
    final id = await db.insert(currencyTable, item.toJson());
    return item.copy(id: id);
  }

  Future<void> insertAll(List<Currency> list) async {
    final db = await _sossoldiDB.database;
    for (Currency currency in list) {
      await db.insert(currencyTable, currency.toJson());
    }
  }

  Future<Currency> selectById(int id) async {
    final db = await _sossoldiDB.database;

    final maps = await db.query(
      currencyTable,
      columns: CurrencyFields.allFields,
      where: '${CurrencyFields.id} = ?',
      whereArgs: [id],
    );

    if (maps.isNotEmpty) {
      return Currency.fromJson(maps.first);
    } else {
      throw Exception('ID $id not found');
    }
  }

  Future<List<Currency>> selectAll() async {
    final db = await _sossoldiDB.database;

    final orderByASC = '${CurrencyFields.id} ASC';

    final result = await db.query(currencyTable, orderBy: orderByASC);

    return result.map((json) => Currency.fromJson(json)).toList();
  }

  Future<int> updateItem(Currency item) async {
    final db = await _sossoldiDB.database;

    return db.update(
      currencyTable,
      item.toJson(),
      where: '${CurrencyFields.id} = ?',
      whereArgs: [item.id],
    );
  }

  Future<int> deleteById(int id) async {
    final db = await _sossoldiDB.database;

    return await db.delete(
      currencyTable,
      where: '${CurrencyFields.id} = ?',
      whereArgs: [id],
    );
  }

  Future<void> changeMainCurrency(int id) async {
    final db = await _sossoldiDB.database;
    await db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE $currencyTable SET ${CurrencyFields.mainCurrency} = 0',
      );
      await txn.rawUpdate(
        'UPDATE $currencyTable SET ${CurrencyFields.mainCurrency} = 1'
        ' WHERE ${CurrencyFields.id} = ?',
        [id],
      );
    });
  }
}
