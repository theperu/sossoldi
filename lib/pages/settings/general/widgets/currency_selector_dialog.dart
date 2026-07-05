import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../constants/style.dart';
import '../../../../model/currency.dart';
import '../../../../providers/currency_provider.dart';
import '../../../../services/currency/currency_display_policy.dart';

class CurrencySelectorDialog {
  static Future<void> _showRecalculationWarning(
    BuildContext context,
    WidgetRef ref,
    Currency selected,
  ) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change main currency?'),
        content: const Text(
          'Historical converted amounts in the transactions list will be recalculated to the selected main currency. This can change previously displayed totals.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref
                  .read(currencyStateProvider.notifier)
                  .setSelectedCurrency(selected);
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
                Navigator.pop(context);
              }
            },
            child: const Text('CONFIRM'),
          ),
        ],
      ),
    );
  }

  static void selectCurrencyDialog(
    BuildContext context,
    Currency currency,
    Future<List<Currency>> currencies,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Select a currency',
          style: Theme.of(context).textTheme.titleLarge!.copyWith(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        content: SizedBox(
          height: 300,
          width: 220,
          child: SingleChildScrollView(
            child: Consumer(
              builder: (context, ref, widget) {
                return FutureBuilder(
                  future: currencies,
                  builder: (context, snapshot) {
                    if (snapshot.hasData &&
                        snapshot.data != null &&
                        snapshot.connectionState == ConnectionState.done) {
                      return ListView.builder(
                        itemCount: snapshot.data!.length,
                        physics: const NeverScrollableScrollPhysics(),
                        shrinkWrap: true,
                        itemBuilder: (BuildContext context, int i) {
                          return GestureDetector(
                            onTap: () {
                              final selected = snapshot.data![i];
                              if (currency.code == selected.code) {
                                Navigator.pop(context);
                                return;
                              }

                              _showRecalculationWarning(
                                context,
                                ref,
                                selected,
                              );
                            },
                            child: ListTile(
                              tileColor: Colors.transparent,
                              leading: CircleAvatar(
                                radius: 22,
                                backgroundColor:
                                    currency.code == snapshot.data![i].code
                                    ? blue5
                                    : grey1,
                                child: Text(
                                  CurrencyDisplayPolicy.displayTokenForCode(snapshot.data![i].code),
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimary,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                              title: Text(
                                snapshot.data![i].name,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        },
                      );
                    } else if (snapshot.hasError) {
                      return Text('Something went wrong: ${snapshot.error}');
                    } else {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Transform.scale(
                          scale: 0.5,
                          child: const CircularProgressIndicator(),
                        );
                      } else {
                        return const Text("Search for a transaction");
                      }
                    }
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
