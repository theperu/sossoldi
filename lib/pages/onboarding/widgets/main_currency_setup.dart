import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:collection/collection.dart';

import '../../../constants/style.dart';
import '../../../model/currency.dart';
import '../../../providers/currency_provider.dart';
import '../../../services/currency/currency_display_policy.dart';
import '../../../services/database/repositories/currency_repository.dart';
import '../../../ui/device.dart';
import 'budget_setup.dart';

class MainCurrencySetup extends ConsumerStatefulWidget {
  const MainCurrencySetup({super.key});

  @override
  ConsumerState<MainCurrencySetup> createState() => _MainCurrencySetupState();
}

class _MainCurrencySetupState extends ConsumerState<MainCurrencySetup> {
  Currency? _selected;

  @override
  Widget build(BuildContext context) {
    final currencyList = ref.watch(_currencyListProvider);

    return Scaffold(
      backgroundColor: blue7,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Sizes.lg),
          child: Column(
            children: [
              Text("STEP 1 OF 3", style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: Sizes.xl),
              Text(
                "Choose your main\ncurrency",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  color: blue1,
                ),
              ),
              const SizedBox(height: Sizes.md),
              Text(
                "Budgets, totals, and transaction list amounts will use this currency.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: blue1,
                ),
              ),
              const SizedBox(height: Sizes.xl),
              Expanded(
                child: currencyList.when(
                  data: (currencies) {
                    if (_selected == null) {
                      final eur = currencies.where((c) => c.code == 'EUR').firstOrNull;
                      _selected = eur ?? (currencies.isNotEmpty ? currencies.first : null);
                    }

                    return ListView.separated(
                      itemCount: currencies.length,
                      separatorBuilder: (_, _) => const SizedBox(height: Sizes.sm),
                      itemBuilder: (context, index) {
                        final currency = currencies[index];
                        final isSelected = _selected?.code == currency.code;
                        return Material(
                          borderRadius: BorderRadius.circular(Sizes.borderRadius),
                          color: isSelected ? blue5 : Theme.of(context).colorScheme.surface,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(Sizes.borderRadius),
                            onTap: () => setState(() => _selected = currency),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: Sizes.lg,
                                vertical: Sizes.md,
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: Sizes.lg,
                                    backgroundColor: isSelected
                                        ? Colors.white.withValues(alpha: 0.2)
                                        : blue5,
                                    child: Text(
                                      CurrencyDisplayPolicy.displayTokenForCode(currency.code),
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.white
                                            : Theme.of(context).colorScheme.onPrimary,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: Sizes.md),
                                  Expanded(
                                    child: Text(
                                      '${currency.name} (${currency.code})',
                                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                        color: isSelected
                                            ? Colors.white
                                            : Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_circle, color: Colors.white),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(child: Text('Error: $err')),
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _selected == null
                      ? null
                      : () async {
                          await ref
                              .read(currencyStateProvider.notifier)
                              .setSelectedCurrency(_selected!);

                          if (context.mounted) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => const BudgetSetup(),
                              ),
                            );
                          }
                        },
                  child: const Text('NEXT STEP'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final _currencyListProvider = FutureProvider<List<Currency>>((ref) async {
  return ref.watch(currencyRepositoryProvider).selectAll();
});
