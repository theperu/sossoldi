# Manual Test Plan: Multi-Currency

**Status:** Active  
**Related fixes:** currency atomicity (#1, #3), silent rate fallback (#2), symbol display (#4), DB hit reduction (#6)  
**Spec:** [multi-currency.md](multi-currency.md)  
**Created:** 27/06/2026

---

## How to read this plan

Each test uses three sections:

- **Preconditions** — exact state the app and data must be in before the first step.
- **Steps** — numbered actions to perform in order.
- **Postconditions** — what must be true for the test to pass.

Tests are grouped by area. Within a group, earlier tests are simpler; later ones cover edge cases and regressions. Work through each group top-to-bottom so each test can build on a known-good baseline.

---

## Shared setup

The following abbreviations are used throughout:

| Term | Meaning |
|------|---------|
| **Main currency** | The app-wide display currency set in Settings → General → Currency |
| **Native currency** | The currency assigned to a specific account |
| **MCA** | A "main-currency account" — an account whose native currency matches the main currency |
| **FCA** | A "foreign-currency account" — an account whose native currency differs from the main currency |
| **Rates present** | The `exchange_rate` table has at least one row for every pair used by the test |
| **Rates absent** | The `exchange_rate` table is empty (fresh install or cleared data) |

---

## Group A — Currency switch: core scenarios

### T1 — Happy-path switch, all same-currency accounts

Verifies the basic successful path.

**Preconditions:**
- Main currency is EUR
- Two or more accounts, all in EUR
- At least five transactions across those accounts
- Rates present (EUR→USD and USD→EUR)

**Steps:**
1. Note the total balance displayed on the dashboard.
2. Note the individual balance for each account in the account list.
3. Note the `amount` shown for the most recent transaction in the transaction list.
4. Go to Settings → General → Currency.
5. Tap USD.
6. Read the confirmation dialog text.
7. Tap **Confirm**.
8. Navigate to the dashboard.
9. Navigate to the account list.
10. Navigate to the transaction list.

**Postconditions:**
- Dashboard total has changed and is approximately `old_total × EUR_USD_rate`.
- Every account balance reflects the USD-equivalent value.
- Transaction amounts reflect USD-converted values.
- No error snack bar appeared at any point.
- Go to Settings → Currency — USD is now highlighted.

---

### T2 — Happy-path switch, mixed-currency accounts

Verifies that each account is converted using its own rate, not a single shared rate.

**Preconditions:**
- Main currency is EUR
- Three accounts: one EUR, one USD, one GBP
- At least three transactions on each account
- Rates present for EUR↔USD, EUR↔GBP, EUR↔JPY

**Steps:**
1. Record the balance and native currency for every account.
2. Switch main currency to JPY.
3. Confirm the dialog.
4. Open each account in turn.

**Postconditions:**
- EUR account balance ≈ `old_EUR_balance × EUR_JPY_rate`.
- USD account balance ≈ `old_USD_balance × USD_JPY_rate` (via EUR cross-rate).
- GBP account balance ≈ `old_GBP_balance × GBP_JPY_rate` (via EUR cross-rate).
- The three conversion multipliers are different from each other (they must not all be 1 or all be the same value).
- Transaction list amounts are in JPY equivalents.

---

### T3 — Switch to the currently selected currency

Verifies that selecting the already-active currency is a no-op.

**Preconditions:**
- Main currency is EUR
- At least one account with a known balance

**Steps:**
1. Note the account balance.
2. Go to Settings → Currency.
3. Tap EUR (the already-selected currency).

**Postconditions:**
- The dialog either does not appear or the action is silently ignored.
- The account balance is unchanged.
- No error is shown.

---

### T4 — Switch rejected when rates are absent (no silent corruption)

This was the **silent-corruption bug**: the old code swallowed all exchange-rate errors and fell back to a 1:1 rate, corrupting every balance with no visible error.

**Preconditions:**
- Fresh install **or** app data cleared so `exchange_rate` table is empty.
- Main currency is EUR.
- At least one FCA (e.g. USD account) with a non-zero balance.
- Record the exact balance of the USD account.

**Steps:**
1. Go to Settings → Currency.
2. Tap GBP.
3. Tap **Confirm** on the dialog.

**Postconditions:**
- An error message is visible (snack bar or dialog containing "Missing FX rate" or equivalent).
- Main currency is still EUR (check Settings → Currency; EUR remains highlighted).
- The USD account balance is **identical** to the value noted in preconditions.
- No transaction's amount has changed.

---

### T5 — Switch with partial rates (some currencies present, some absent)

Verifies that a single missing rate aborts the entire operation, leaving no partial update.

**Preconditions:**
- Main currency is EUR.
- Two FCAs: one USD (rate EUR→USD present), one JPY (rate EUR→JPY **absent**).
- Multiple transactions on each account.
- Record all balances.

**Steps:**
1. Switch main currency to GBP.
2. Confirm.

**Postconditions:**
- An error is shown.
- Main currency remains EUR.
- **Both** account balances are unchanged — not just the JPY one.
- This confirms the pre-validation step ran before any writes (atomicity).

---

### T6 — Round-trip switch preserves approximate values

Verifies that switching away and back produces values close to the originals, ruling out silent 1:1 fallbacks.

**Preconditions:**
- Main currency is EUR.
- At least one FCA with a non-zero balance.
- Record all account balances.
- Rates present for EUR↔GBP.

**Steps:**
1. Switch main currency to GBP.
2. Confirm; note the new GBP-denominated balances.
3. Switch main currency back to EUR.
4. Confirm.
5. Compare the final EUR balances to those recorded in preconditions.

**Postconditions:**
- Final EUR balances differ from original by no more than a few cents (floating-point rounding only).
- A large difference (e.g. a balance that was €500 now showing €500 exactly despite a real EUR/GBP rate ≠ 1) indicates a 1:1 fallback was applied on one of the legs.

---

## Group B — Currency switch: data integrity

### T7 — Currency flag persists across force-close

Verifies that the `mainCurrency` flag is written atomically so no crash window leaves all currencies unselected.

**Preconditions:**
- Main currency is EUR.
- Rates present.

**Steps:**
1. Switch main currency to GBP and confirm.
2. Verify the switch completed (Settings → Currency shows GBP).
3. Force-close the app from the OS task switcher.
4. Reopen the app.

**Postconditions:**
- App opens with GBP as main currency.
- Dashboard totals are in GBP.
- Settings → Currency still shows GBP highlighted.
- EUR is **not** selected (the old bug: two un-transacted UPDATEs meant a crash between them left `mainCurrency = 0` for all rows, causing a silent fallback to hardcoded EUR).

---

### T8 — All accounts updated atomically, none left behind

Verifies every account's `startingValueInMainCurrency` is updated in a single transaction.

**Preconditions:**
- Main currency is EUR.
- Five accounts in different currencies (EUR, USD, GBP, JPY, CHF).
- Rates present for all pairs.

**Steps:**
1. Record the balance for each account.
2. Switch main currency to USD.
3. Confirm.
4. Open each account individually and check its displayed balance.

**Postconditions:**
- Every account shows a USD-converted balance.
- No account still shows an EUR balance.
- The ratios between accounts are consistent with the exchange rates (a €1000 EUR account and a $1000 USD account should not show the same USD value).

---

### T9 — All transactions updated atomically, none left behind

Verifies every transaction's `amountInMainCurrency` is updated.

**Preconditions:**
- Main currency is EUR.
- Three accounts in EUR, USD, and GBP each with at least five transactions.
- Rates present.

**Steps:**
1. Note the total income and total expense shown in the transaction list for the current month.
2. Switch main currency to CHF.
3. Confirm.
4. Return to the transaction list.
5. Scroll through all transactions.

**Postconditions:**
- Every transaction shows a CHF-denominated primary amount.
- No transaction still shows a EUR, USD, or GBP primary amount.
- The monthly income and expense totals have changed proportionally.

---

## Group C — Exchange rate management

### T10 — Fetch rates from the network

**Preconditions:**
- Device has internet access.
- `exchange_rate` table may be empty or have old data.

**Steps:**
1. Go to Settings → General.
2. Locate the "Update exchange rates" control (or equivalent).
3. Trigger a rate update.

**Postconditions:**
- No error is shown.
- A "last updated" date or similar indicator updates to today's date.
- The `exchange_rate` table now contains rows for the main currency paired with each supported currency.

---

### T11 — Fetch fails when offline; cached rates retained

**Preconditions:**
- Rates were previously fetched successfully (rows exist in `exchange_rate`).
- Note the staleness date shown in Settings.
- Disable the device's network connection.

**Steps:**
1. Trigger a rate update.

**Postconditions:**
- An error is shown or the update silently fails; no crash.
- The staleness date in Settings is **unchanged** (it must not advance on a failed fetch).
- The rows previously in `exchange_rate` are unchanged.

---

### T12 — Stale cached rates are used for transactions

**Preconditions:**
- Rates were fetched at least one day ago.
- Device is offline.
- Main currency is EUR; at least one FCA (USD account).

**Steps:**
1. Create a new expense on the USD account.

**Postconditions:**
- Transaction saves successfully.
- The transaction's converted amount uses the cached rate (the app does not refuse to save because rates are stale).
- The rate-age indicator next to the converted amount shows the date of the cached rate.

---

### T13 — Rate date is shown on transaction form when account currency differs from main

**Preconditions:**
- Main currency is EUR; one FCA (GBP account).
- Rates present.

**Steps:**
1. Open the "New Transaction" form.
2. Select the GBP account.
3. Enter any amount.

**Postconditions:**
- Somewhere on the form (below or next to the converted amount), a line is visible showing the rate and its date, e.g. `1 GBP = 1.17 EUR (rate from 2026-06-25)`.
- This line is visible **always**, not only when the rate is stale.

---

## Group D — Transaction creation and editing

### T14 — Create income on a foreign-currency account

**Preconditions:**
- Main currency is EUR; one FCA (USD account with current balance noted).
- Rates present (EUR→USD).

**Steps:**
1. Create an income transaction of USD 200 on the USD account.
2. Save.
3. Open the transaction list.
4. Tap the transaction to view details.
5. Check the USD account balance in the account list.

**Postconditions:**
- Transaction list shows the EUR-equivalent primary amount (approx. `200 / EUR_USD_rate`).
- Transaction detail shows USD 200 as the native amount.
- The USD account balance increased by exactly USD 200 in native terms.
- `amountInMainCurrency` is set (not null) and reflects the EUR equivalent.

---

### T15 — Create expense on a foreign-currency account

**Preconditions:**
- Same as T14 but creating an expense.

**Steps:**
1. Create an expense of USD 50 on the USD account.
2. Save.

**Postconditions:**
- USD account balance decreased by exactly USD 50.
- Transaction list shows the EUR-equivalent as a negative value.
- No error occurred.

---

### T16 — Create transaction on FCA when rates are absent

**Preconditions:**
- `exchange_rate` table is empty.
- Main currency is EUR; one FCA (USD account).

**Steps:**
1. Open the "New Transaction" form.
2. Select the USD account.
3. Enter an amount.
4. Tap **Save**.

**Postconditions:**
- Save is **blocked** with a visible error message about missing rates.
- An inline "Fetch latest rates" action is available.
- No transaction is created.

---

### T17 — Inline rate fetch unblocks transaction save

Continuation of T16.

**Preconditions:**
- T16 completed; the error with a "Fetch latest rates" action is visible.
- Device has internet access.

**Steps:**
1. Tap the "Fetch latest rates" action in the error.
2. After the fetch completes, tap **Save** again.

**Postconditions:**
- Transaction saves successfully.
- Transaction appears in the transaction list with a correct EUR-equivalent amount.

---

### T18 — Edit transaction amount recalculates `amountInMainCurrency`

**Preconditions:**
- Main currency is EUR; one FCA (GBP account).
- An existing GBP transaction of £100; its EUR-equivalent noted.
- Rates present.

**Steps:**
1. Open the existing GBP transaction.
2. Change the amount to £200.
3. Save.

**Postconditions:**
- The transaction's primary (EUR) amount is approximately double what it was before.
- The native GBP amount shows £200.

---

### T19 — Edit transaction — change account changes the currency context

**Preconditions:**
- Main currency is EUR.
- One EUR account and one GBP account.
- An existing EUR income transaction of €100.
- Rates present.

**Steps:**
1. Open the EUR transaction.
2. Change the account to the GBP account.
3. Save.

**Postconditions:**
- The transaction is now stored with `currency = GBP`.
- `amountInMainCurrency` is recalculated using the GBP→EUR rate.
- The transaction appears in the GBP account's history.

---

### T20 — Duplicate transaction preserves currency

**Preconditions:**
- Main currency is EUR; one FCA (JPY account) with at least one transaction.

**Steps:**
1. Open the JPY transaction.
2. Tap the duplicate icon.
3. Confirm the duplicate dialog.

**Postconditions:**
- A new transaction appears with `currency = JPY`.
- `amountInMainCurrency` on the duplicate is set (not null) and matches the original's converted amount.
- The JPY account balance reflects both transactions.

---

## Group E — Transfers

### T21 — Same-currency transfer

**Preconditions:**
- Main currency is EUR; two EUR accounts with known balances.
- Rates present.

**Steps:**
1. Create a transfer of €150 from Account A to Account B.
2. Save.
3. Check both account balances.

**Postconditions:**
- Account A balance decreased by €150.
- Account B balance increased by €150.
- The transfer does not appear in the income/expense day totals (transfers are excluded).
- `amountInMainCurrency` on the transfer equals €150.

---

### T22 — Cross-currency transfer pre-fills destination amount

**Preconditions:**
- Main currency is EUR; one EUR account and one USD account.
- Rates present (EUR→USD).

**Steps:**
1. Open "New Transaction" → Transfer.
2. Select the EUR account as source, USD account as destination.
3. Enter €100 as the source amount.
4. Observe the destination amount field.

**Postconditions:**
- The destination amount field is pre-filled with approximately `100 × EUR_USD_rate` USD.
- The rate used and its date are visible on the form.

---

### T23 — Cross-currency transfer with manual destination override

Continuation of T22.

**Steps:**
1. Manually change the destination amount to a different value (e.g. $115 instead of the pre-filled $108).
2. Save.
3. Check both account balances.

**Postconditions:**
- EUR account decreased by €100.
- USD account increased by exactly $115 (the manually entered amount).
- `transferDestinationAmount` stored on the transaction is $115.
- `transferEffectiveRate` is `115 / 100 = 1.15`.

---

### T24 — Cross-currency transfer blocked when rates absent

**Preconditions:**
- `exchange_rate` table is empty.
- One EUR account, one USD account.

**Steps:**
1. Attempt to create a transfer from EUR to USD account.

**Postconditions:**
- The form is blocked or save is rejected with a visible error.
- No transaction is created.

---

## Group F — Account balances and net worth

### T25 — Account list shows native currency primary and main currency secondary

**Preconditions:**
- Main currency is EUR.
- One FCA (USD account) with a non-zero balance.

**Steps:**
1. Open the account list.
2. Locate the USD account row.

**Postconditions:**
- The primary balance displays in USD with the `$` symbol.
- A secondary line displays the EUR-equivalent with the `€` symbol.
- The two values are different (assuming USD ≠ EUR rate).

---

### T26 — Dashboard net worth uses main-currency equivalents

**Preconditions:**
- Main currency is EUR.
- Two accounts: one EUR (€1,000), one USD ($500).
- `countNetWorth = true` on both.
- Rates present (assume EUR→USD = 1.1, so $500 = €454.55).

**Steps:**
1. Open the dashboard.
2. Read the net worth total.

**Postconditions:**
- Net worth ≈ €1,000 + €454.55 = €1,454.55 (varies with actual rate).
- Net worth is **not** €1,500 (which would indicate the USD balance was added as-is without conversion).

---

### T27 — Account excluded from net worth via `countNetWorth = false`

**Preconditions:**
- Main currency is EUR.
- One EUR account with `countNetWorth = true` (€800).
- One USD account with `countNetWorth = false` ($2,000).

**Steps:**
1. Open the dashboard.
2. Read the net worth total.

**Postconditions:**
- Net worth ≈ €800 only; the USD account is excluded.

---

## Group G — Budgets and statistics

### T28 — Budget spending uses `amountInMainCurrency`

**Preconditions:**
- Main currency is EUR.
- One FCA (USD account).
- A budget for category "Food" of €100/month.
- Create a Food expense of $50 on the USD account (≈ €45 at current rate).

**Steps:**
1. Open the Planning / Budget screen.
2. Find the "Food" budget.

**Postconditions:**
- The budget shows approximately €45 spent out of €100, not $50 out of €100.

---

### T29 — Statistics income/expense chart uses `amountInMainCurrency`

**Preconditions:**
- Main currency is EUR.
- One FCA (GBP account) with a £200 income transaction this month.
- One MCA (EUR account) with a €100 income transaction this month.

**Steps:**
1. Open the Statistics / Graphs screen.
2. View the current month income bar.

**Postconditions:**
- Total income shown ≈ (£200 × GBP_EUR_rate) + €100.
- Income is **not** shown as £200 + €100 = €300 (which would indicate no conversion).

---

## Group H — Onboarding

### T30 — Onboarding currency selection sets the main currency

**Preconditions:**
- Fresh install (or reset to re-run onboarding).

**Steps:**
1. Launch the app.
2. On the "Choose your main currency" step, select JPY.
3. Tap **Next Step**.
4. Complete the rest of onboarding.
5. Go to Settings → Currency.

**Postconditions:**
- JPY is selected as the main currency.
- Dashboard totals are displayed with the `¥` symbol.
- Account creation form defaults the currency to JPY.

---

### T31 — Onboarding currency screen shows correct symbols for all currencies

**Preconditions:**
- Fresh install.

**Steps:**
1. On the "Choose your main currency" screen, scroll through the full list.

**Postconditions:**
- Same symbol assertions as T32 (see Group I) — no two currencies share the same symbol.
- EUR is pre-selected by default.

---

## Group I — Settings UI

### T32 — Currency selector shows disambiguated symbols

**Preconditions:**
- Any app state. Open **Settings → General → Currency**.

**Steps:**
1. Scroll through the full currency list.
2. Note the symbol shown inside the circle avatar for each currency below.

| Currency | Must show | Must NOT show |
|----------|-----------|---------------|
| US Dollar | `$` | — |
| Canadian Dollar | `C$` | `$` |
| Australian Dollar | `A$` | `$` |
| New Zealand Dollar | `NZ$` | `$` |
| Hong Kong Dollar | `HK$` | `$` |
| Singapore Dollar | `S$` | `$` |
| Mexican Peso | `MX$` | `$` |
| Euro | `€` | — |
| British Pound | `£` | — |
| Japanese Yen | `¥` | — |

**Postconditions:**
- No two currencies in the list share the same symbol.

---

### T33 — Cancel on currency switch dialog makes no change

**Preconditions:**
- Main currency is EUR. Note all account balances.

**Steps:**
1. Go to Settings → Currency.
2. Tap a different currency (e.g. GBP).
3. When the confirmation dialog appears, tap **Cancel**.

**Postconditions:**
- Main currency remains EUR.
- All account balances are unchanged.
- Settings → Currency still shows EUR highlighted.

---

## Group J — Database migration and upgrades

### T34 — Fresh install: correct initial state

**Preconditions:**
- App installed for the first time (no prior data).

**Steps:**
1. Complete onboarding (select EUR as main currency).
2. Create one account.
3. Create one transaction.

**Postconditions:**
- The account has `currency = EUR` and `startingValueInMainCurrency = startingValue`.
- The transaction has `currency = EUR` and `amountInMainCurrency = amount`.
- The `exchange_rate` table exists (may be empty before first fetch).
- The `currency` table contains all 21 supported currencies.

---

### T35 — Upgrade from pre-multi-currency version (migration 0007 → 0008)

**Preconditions:**
- Device has an existing install at DB version 7 (pre-multi-currency) with:
  - At least two accounts with non-zero balances.
  - At least ten transactions.

**Steps:**
1. Install the new version over the existing one (do not clear data).
2. Launch the app.

**Postconditions:**
- App launches without crashing.
- All existing accounts have `currency = EUR` (the previous implicit default).
- All existing accounts have `startingValueInMainCurrency = startingValue`.
- All existing transactions have `currency = NULL` (pre-feature rows; the app treats these as main currency via `COALESCE`).
- All existing transactions have `amountInMainCurrency = amount`.
- Account balances in the account list match what they showed before the upgrade.
- Net worth total matches pre-upgrade.

---

### T36 — Legacy transactions with null currency are handled correctly

**Preconditions:**
- At least one transaction with `currency = NULL` (created before migration 0008).
- Main currency is EUR.

**Steps:**
1. View the transaction list.
2. Switch main currency to USD.
3. Confirm.

**Postconditions:**
- The `NULL`-currency transactions are treated as EUR (the previous main currency) when computing their USD-converted `amountInMainCurrency`.
- After the switch, those transactions show a USD-converted amount, not zero or an error.
- No crash.

---

## Group K — Edge cases

### T37 — Account with zero transactions

**Preconditions:**
- Main currency is EUR.
- One FCA (CHF account) with a non-zero `startingValue` and no transactions.
- Rates present.

**Steps:**
1. Note the CHF account balance (should equal `startingValue`).
2. Switch main currency to GBP.
3. Confirm.
4. Check the CHF account balance.

**Postconditions:**
- No crash.
- `startingValueInMainCurrency` was updated: balance ≈ `startingValue × CHF_GBP_rate`.

---

### T38 — Account with zero starting value

**Preconditions:**
- Main currency is EUR.
- One FCA (USD account) with `startingValue = 0` and several transactions totalling $300.
- Rates present.

**Steps:**
1. Note the USD account total (should be $300).
2. Switch main currency to GBP.
3. Confirm.

**Postconditions:**
- No crash.
- USD account total ≈ $300 × USD_GBP_rate in GBP.

---

### T39 — Recurring transaction fires after a currency switch

**Preconditions:**
- Main currency is EUR.
- One FCA (USD account) with a monthly recurring income of $100.
- Switch main currency to GBP.
- Rates present.

**Steps:**
1. Trigger the recurring transaction to fire (advance the date or use the manual trigger if available).
2. Check the transaction list for the new recurring entry.

**Postconditions:**
- The new recurring transaction's `currency = USD`.
- `amountInMainCurrency` is calculated using the current cached GBP rate (not the EUR rate from before the switch).

---

### T40 — Multiple rapid currency switches do not leave inconsistent state

**Preconditions:**
- Main currency is EUR.
- Rates present for EUR, USD, GBP, JPY.
- At least one FCA.

**Steps:**
1. Switch main currency to USD. Confirm. Wait for completion.
2. Immediately switch to GBP. Confirm. Wait for completion.
3. Immediately switch to JPY. Confirm. Wait for completion.
4. Check all account balances and the main currency in Settings.

**Postconditions:**
- After each switch, the selected currency updates correctly in Settings.
- After step 3, all balances are in JPY.
- No account or transaction is left in a partially-switched state.

---

### T41 — Offline switch using cached rates

**Preconditions:**
- Rates were fetched successfully (rows in `exchange_rate`).
- Disable the device's network connection.
- Main currency is EUR; one FCA (USD account).

**Steps:**
1. Switch main currency to GBP.
2. Confirm.

**Postconditions:**
- Switch completes using the cached rates.
- No error is shown.
- All balances are converted to GBP.

---

### T42 — Offline switch with no cached rates

**Preconditions:**
- `exchange_rate` table is empty.
- Device is offline.
- Main currency is EUR; one FCA (USD account).
- Record all balances.

**Steps:**
1. Attempt to switch main currency to GBP.
2. Confirm.

**Postconditions:**
- An error is shown.
- Main currency remains EUR.
- All balances are unchanged.

---

## Group L — Import / Export

The export writes every DB table — including `currency`, `exchange_rate`, `bankAccount`, and `transaction` — into a single CSV file with a leading `table_name` column. Import clears and restores each table inside a single DB transaction.

---

### T43 — Export includes all multi-currency columns

Verifies that the exported file contains the new columns added by migration 0008.

**Preconditions:**
- Main currency is EUR.
- At least one FCA (USD account) with at least one transaction.
- Rates present in `exchange_rate`.

**Steps:**
1. Go to Settings → Backup.
2. Tap **Export**.
3. Save the file and open it in a text editor or spreadsheet app.
4. Find the header row.
5. Find rows where `table_name = bankAccount`.
6. Find rows where `table_name = transaction`.
7. Find rows where `table_name = exchange_rate`.
8. Find rows where `table_name = currency`.

**Postconditions:**
- Header row contains `currency`, `startingValueInMainCurrency`, `amountInMainCurrency`, `transferDestinationAmount`, `transferEffectiveRate`.
- `bankAccount` rows have non-empty values for `currency` and `startingValueInMainCurrency`.
- `transaction` rows have non-empty values for `amountInMainCurrency`; `currency` is non-empty for transactions created after migration 0008 and empty for legacy rows.
- `exchange_rate` rows are present (one per currency pair that was fetched).
- `currency` rows are present; exactly one row has `mainCurrency = 1` (EUR).

---

### T44 — Full round-trip: export then import on the same device

Verifies that importing a file that was just exported restores the app to an identical state.

**Preconditions:**
- Main currency is EUR.
- Two accounts: one EUR (€500 balance), one USD ($300 balance).
- At least five transactions across both accounts.
- Rates present.

**Steps:**
1. Note: main currency, all account balances, transaction count, and the balance of each account.
2. Export the data (Settings → Backup → Export). Save the file.
3. Create a new dummy transaction (e.g. €1 expense) to change the state.
4. Go to Settings → Backup → Import.
5. Select the file saved in step 2.
6. Confirm the import (app will restart).

**Postconditions:**
- Main currency is EUR.
- EUR account balance is €500 (the dummy transaction from step 3 is gone).
- USD account balance is $300.
- Transaction count matches the value noted in step 1.
- No error was shown during import.
- Exchange rates are restored; a currency switch can be performed immediately without fetching rates.

---

### T45 — Import restores the correct main currency

Verifies that after import, `mainCurrency` on the `currency` table is set correctly, not silently reset to EUR.

**Preconditions:**
- Main currency is **JPY** (not the default EUR).
- At least one account and a few transactions.

**Steps:**
1. Export the data.
2. Switch main currency to EUR (to change the DB state away from JPY).
3. Import the file exported in step 1.
4. After the app restarts, go to Settings → Currency.

**Postconditions:**
- JPY is highlighted as the main currency.
- Dashboard totals are displayed in JPY with the `¥` symbol.
- Exactly one currency has `mainCurrency = 1` in the restored data.

---

### T46 — Import from a CSV with no main currency set (corrupted flag)

Verifies graceful handling of a CSV where all `currency` rows have `mainCurrency = 0` (e.g. a CSV exported during the old two-UPDATE race-condition window).

**Preconditions:**
- A CSV file manually edited so every `currency` row has `mainCurrency = 0`.

**Steps:**
1. Go to Settings → Backup → Import.
2. Select the edited file.
3. Confirm.
4. After the app restarts, check Settings → Currency and the dashboard.

**Postconditions:**
- The app does not crash on import or restart.
- The app falls back to a usable state (EUR selected, or a visible prompt to re-select a main currency).
- Balances are not corrupted (no silent 1:1 conversion applied).

---

### T47 — Import a CSV exported before multi-currency (missing columns)

Verifies backward compatibility when importing a backup that predates migration 0008 and therefore has no `currency`, `amountInMainCurrency`, or `exchange_rate` columns.

**Preconditions:**
- A CSV file from an older app version that does not contain `currency`, `startingValueInMainCurrency`, `amountInMainCurrency`, or `exchange_rate` rows.

**Steps:**
1. Go to Settings → Backup → Import.
2. Select the old CSV file.
3. Confirm.
4. After the app restarts, check account balances and the transaction list.

**Postconditions:**
- Import completes without crashing.
- Accounts are restored with `currency = EUR` and `startingValueInMainCurrency = startingValue` (migration defaults).
- Transactions are restored with `currency = NULL` and `amountInMainCurrency = amount` (COALESCE fallback applies).
- Account balances match what the old app showed.
- A currency switch is possible after fetching rates.

---

### T48 — Export after a currency switch includes updated converted amounts

Verifies that the CSV reflects the post-switch values, not the pre-switch values.

**Preconditions:**
- Main currency starts as EUR.
- One FCA (USD account, $400 balance).
- Switch main currency to GBP successfully.
- Note the GBP-equivalent balance of the USD account.

**Steps:**
1. Export the data.
2. Open the CSV.
3. Find the `bankAccount` row for the USD account.
4. Find all `transaction` rows for that account.

**Postconditions:**
- `startingValueInMainCurrency` for the USD account reflects the GBP-converted value (not the old EUR value).
- `amountInMainCurrency` for USD transactions reflects GBP-converted values.
- The `currency` row for GBP has `mainCurrency = 1`; EUR has `mainCurrency = 0`.

---

### T49 — Import into a device with different rates than the exporting device

Verifies that `exchange_rate` rows are restored from the file and used as-is, not overwritten by the importing device's rates.

**Preconditions:**
- Device A: rates fetched on 2026-06-20. Export the data.
- Device B: rates fetched on 2026-06-27 (different date, different rate values). Import Device A's file.

**Steps:**
1. On Device B, note the rate date shown in Settings → General before importing.
2. Import Device A's file on Device B.
3. After restart, check the rate date shown in Settings.

**Postconditions:**
- Settings shows the rate date from Device A's file (2026-06-20), not Device B's previous date.
- Device B's pre-import rates are replaced by Device A's.
- Account balances reflect the rates from the imported file.

---

### T50 — Import fails gracefully for a malformed CSV

**Preconditions:**
- Any app state with data.
- A CSV file that is not a valid Sossoldi export (e.g. a spreadsheet export from a third-party app, or a truncated file).
- Record all account balances before importing.

**Steps:**
1. Go to Settings → Backup → Import.
2. Select the malformed file.
3. Confirm.

**Postconditions:**
- An error message is shown describing the failure.
- The app does not crash.
- All account balances and transactions are **unchanged** (the import transaction was rolled back).
- The main currency is unchanged.

