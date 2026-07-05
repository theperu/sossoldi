import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../ui/device.dart';
import '../../../../ui/extensions.dart';
import '../linear_progress_bar.dart';
import '../../../../ui/widgets/default_container.dart';
import '../../../../providers/accounts_provider.dart';
import '../../../../model/bank_account.dart';
import '../../../../services/currency/currency_display_policy.dart';
import '../card_label.dart';

class AccountsCard extends ConsumerWidget {
  const AccountsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountList = ref.watch(activeAccountsProvider);

    return Column(
      children: [
        const CardLabel(label: "Accounts"),
        const SizedBox(height: Sizes.sm),
        DefaultContainer(
          child: accountList.when(
            data: (accounts) => ListView.separated(
              itemCount: accounts.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              scrollDirection: Axis.vertical,
              separatorBuilder: (context, i) =>
                  const SizedBox(height: Sizes.xs),
              itemBuilder: (context, i) {
                final total = accounts.isNotEmpty
                    ? accounts
                          .map(
                            (account) => (account.totalInMainCurrency ??
                                    account.total ??
                                    0)
                                .toDouble(),
                          )
                          .reduce(
                            (first, second) => first > second ? first : second,
                          )
                    : 0.0;
                BankAccount account = accounts[i];
                final accountTotalInMainCurrency =
                    (account.totalInMainCurrency ?? account.total ?? 0)
                        .toDouble();
                return SizedBox(
                  height: Sizes.xl * 2,
                  child: Column(
                    spacing: 4,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: account.name,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            "${account.total?.toCurrency()}${CurrencyDisplayPolicy.displayTokenForCode(account.currency)}",
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                      LinearProgressBar(
                        type: BarType.account,
                        amount: accountTotalInMainCurrency,
                        total: total,
                        colorIndex: account.color,
                      ),
                    ],
                  ),
                );
              },
            ),
            loading: () => const SizedBox.shrink(),
            error: (e, s) => Text('Error: $e'),
          ),
        ),
      ],
    );
  }
}
