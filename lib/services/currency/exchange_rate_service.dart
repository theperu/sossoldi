import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../model/exchange_rate.dart';
import 'currency_display_policy.dart';
import '../database/repositories/currency_repository.dart';
import '../database/repositories/exchange_rate_repository.dart';

class ExchangeRateService {
  ExchangeRateService({
    required ExchangeRateRepository exchangeRateRepository,
    required CurrencyRepository currencyRepository,
  }) : _exchangeRateRepository = exchangeRateRepository,
       _currencyRepository = currencyRepository;

  final ExchangeRateRepository _exchangeRateRepository;
  final CurrencyRepository _currencyRepository;

  Future<String> _getMainCurrencyCode() async {
    return (await _currencyRepository.getSelectedCurrency()).code;
  }

  Future<double> getRate({required String from, required String to}) async {
    if (from == to) {
      return 1;
    }

    final main = await _getMainCurrencyCode();

    if (from == main) {
      final direct = await _exchangeRateRepository.getLatestRate(
        base: main,
        target: to,
      );
      if (direct == null) {
        throw Exception('Missing FX rate for $from->$to');
      }
      return direct.rate;
    }

    if (to == main) {
      final inverse = await _exchangeRateRepository.getLatestRate(
        base: main,
        target: from,
      );
      if (inverse == null || inverse.rate == 0) {
        throw Exception('Missing FX rate for $from->$to');
      }
      return 1 / inverse.rate;
    }

    final mainToFrom = await _exchangeRateRepository.getLatestRate(
      base: main,
      target: from,
    );
    final mainToTo = await _exchangeRateRepository.getLatestRate(
      base: main,
      target: to,
    );

    if (mainToFrom == null || mainToTo == null || mainToFrom.rate == 0) {
      throw Exception('Missing FX rate for $from->$to');
    }

    return mainToTo.rate / mainToFrom.rate;
  }

  Future<String?> getRateDate({required String from, required String to}) async {
    if (from == to) {
      return null;
    }

    final main = await _getMainCurrencyCode();
    if (from == main) {
      return _exchangeRateRepository.getLatestRateDate(base: main, target: to);
    }

    if (to == main) {
      return _exchangeRateRepository.getLatestRateDate(
        base: main,
        target: from,
      );
    }

    final fromDate = await _exchangeRateRepository.getLatestRateDate(
      base: main,
      target: from,
    );
    final toDate = await _exchangeRateRepository.getLatestRateDate(
      base: main,
      target: to,
    );

    if (fromDate == null) {
      return toDate;
    }
    if (toDate == null) {
      return fromDate;
    }
    return fromDate.compareTo(toDate) < 0 ? fromDate : toDate;
  }

  Future<double> convertToMain(double amount, String currency) async {
    final main = await _getMainCurrencyCode();
    if (currency == main) return amount;
    final inverse = await _exchangeRateRepository.getLatestRate(
      base: main,
      target: currency,
    );
    if (inverse == null || inverse.rate == 0) {
      throw Exception('Missing FX rate for $currency->$main');
    }
    return amount / inverse.rate;
  }

  Future<String?> latestRateDate() async {
    return _exchangeRateRepository.getMaxDate();
  }

  Future<void> updateAll() async {
    final main = await _getMainCurrencyCode();
    final mainLower = main.toLowerCase();
    final uris = [
      Uri.parse(
        'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/$mainLower.json',
      ),
      Uri.parse('https://latest.currency-api.pages.dev/v1/currencies/$mainLower.json'),
    ];

    Map<String, dynamic>? payload;
    for (final uri in uris) {
      try {
        final response = await http.get(uri);
        if (response.statusCode == 200) {
          payload = jsonDecode(response.body) as Map<String, dynamic>;
          break;
        }
      } catch (_) {
        // Try next endpoint.
      }
    }

    if (payload == null) {
      throw Exception('Unable to fetch latest exchange rates');
    }

    final date = (payload['date'] as String?) ?? DateTime.now().toIso8601String().substring(0, 10);
    final ratesRoot = payload[mainLower];
    if (ratesRoot is! Map<String, dynamic>) {
      throw Exception('Unexpected exchange rate payload');
    }

    final now = DateTime.now();
    final entries = <ExchangeRate>[];

    for (final code in CurrencyDisplayPolicy.symbolsByCode.keys) {
      if (code == main) continue;

      final value = ratesRoot[code.toLowerCase()];
      if (value is num) {
        entries.add(
          ExchangeRate(
            baseCurrency: main,
            targetCurrency: code,
            rate: value.toDouble(),
            date: date,
            createdAt: now,
          ),
        );
      }
    }

    if (entries.isEmpty) {
      throw Exception('No exchange rates found for $main');
    }

    await _exchangeRateRepository.upsertAll(entries);
  }
}
