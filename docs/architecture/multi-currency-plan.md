# Implementation Plan: Multi-Currency Support

**Spec:** [multi-currency.md](multi-currency.md)  
**Migration version:** `0008`  
**New dependency:** `package:http`

Progress key: `[ ]` not started · `[~]` in progress · `[x]` done

---

## Guardrails (Do Not Regress)

- Main currency is collected in onboarding before first account and budget setup
- Transaction list amount is always displayed in main currency (`amountInMainCurrency` fallback `amount`)
- Every account amount uses the account's native currency symbol, never `currencyState.symbol` unless the value is explicitly main-currency

---

## Decision Log (Grilling Session)

- [x] Onboarding order is fixed to: Main Currency -> Budget Setup -> Account Setup
- [x] Transaction list shows only main-currency amount (no native secondary line)
- [x] Transfers remain excluded from day/group totals (contribution = 0)
- [x] Account-native displays append ISO code only for ambiguous symbols
- [x] Ambiguity is computed dynamically from the `currency` table (same symbol used by multiple codes)
- [x] For shared-symbol families, USD keeps `$`; other currencies in that family use ISO code for clarity
- [x] USD-preferred shared-symbol rule applies everywhere (inputs and read-only displays)
- [x] Onboarding default main currency is always EUR (no locale-based auto selection)
- [x] No explicit old-user repair UX flow is required; invariant assumed by product constraints
- [x] Onboarding first account currency is fixed to selected main currency
- [x] Amount entry in create/edit transaction uses selected source account currency
- [x] Transactions list uses a two-line trailing amount block: main-currency primary + native secondary when different
- [x] No USD fallback defaults anywhere in provider/repository startup paths
- [x] Main currency change recalculates historical main-currency amounts and requires a warning/confirmation before apply
- [x] Main currency warning flow is one-step confirmation (no preview step)
- [x] Transfer list presentation remains one logical row (aligned with current single-row transfer storage model)
- [x] Cross-currency transfers store destination amount explicitly
- [x] Cross-currency transfers store effective FX rate used at save time
- [x] Transfer list primary amount uses source-side main-currency equivalent; transfer remains excluded from totals
- [x] Editing old transfers keeps locked FX values by default; explicit recompute toggle is deferred to v2.0
- [x] Budgets remain main-currency only for input and display, using the same symbol policy
- [x] Legacy history keeps permanent fallback `amountInMainCurrency ?? amount`; no backfill migration required
- [x] Current multi-currency migration has not shipped; schema changes can still be folded into `0008`
- [x] Account-specific surfaces show native primary + main-currency secondary; aggregate surfaces remain main-currency only
- [x] Supported currencies and display symbol policy are hardcoded centrally
- [x] Saving foreign-currency account/transaction is blocked when FX rate is missing
- [x] Blocking UX includes inline "Fetch latest rates" action with one auto-retry after successful fetch
- [x] Converted values are stored at high precision; rounding is display-only

---

## Repository Impact Map (Validated)

- **Onboarding route/gating**
  - `lib/main.dart` currently routes first-run users to `/onboarding` only via `onboarding_completed`
  - `lib/pages/onboarding/onboarding_page.dart` currently starts with budget setup
  - `lib/pages/onboarding/widgets/budget_setup.dart` currently labeled "STEP 1 OF 2" and assumes budget-first
  - `lib/pages/onboarding/widgets/account_setup.dart` currently labeled "STEP 2 OF 2" and hardcodes `€` in amount input hint/suffix
- **Budget setup uses main currency display today**
  - `lib/pages/planning/manage_budget_page.dart`
  - `lib/pages/planning/widget/budget_category_selector.dart`
  - `lib/pages/planning/widget/budget_card.dart`
  - `lib/pages/onboarding/widgets/add_budget_dialog.dart`
- **Transaction list and grouped totals still use native `amount` in places**
  - `lib/ui/widgets/transactions_list.dart` (tile amount + day total)
  - `lib/pages/transactions/widgets/panel_list_tile.dart` (group header sums)
- **Account amount symbol risks (global symbol used where account symbol is required)**
  - `lib/pages/dashboard/widgets/accounts_sum.dart`
  - `lib/pages/accounts/account_page.dart`
  - `lib/pages/graphs/widgets/accounts/accounts_card.dart`
- **Aggregate analytics expected to remain main-currency**
  - `lib/pages/transactions/widgets/custom_sliver_delegate.dart`
  - `lib/pages/transactions/widgets/accounts_pie_chart.dart`
  - `lib/pages/graphs/widgets/categories/*`

---

## Phase 0 — Onboarding Main Currency (Critical)

- [ ] **0.1** Add onboarding step in `lib/pages/onboarding/` for required main-currency selection
  - Blocking step: cannot continue to account/budget setup without selection
  - Default from locale when available; user can change
  - Insert this as the first onboarding step before current budget setup
- [ ] **0.2** Persist onboarding selection as app main currency via `CurrencyRepository.changeMainCurrency`
- [ ] **0.3** Wire downstream defaults
  - First account creation defaults to selected main currency
  - Initial budget setup/evaluation uses selected main currency
- [ ] **0.4** Migration path for existing users
  - If exactly one main currency already exists, onboarding stays skipped
  - If data inconsistency is detected (none or multiple mains), show currency-fix flow before app usage
- [ ] **0.5** Re-sequence onboarding copy and labels
  - `budget_setup.dart`: update from "STEP 1 OF 2" to "STEP 2 OF 3"
  - `account_setup.dart`: update from "STEP 2 OF 2" to "STEP 3 OF 3"
  - `account_setup.dart`: replace hardcoded euro hint/suffix with selected main currency symbol

---

## Phase 1 — Dependencies & Database

- [x] **1.1** Add `http` to `pubspec.yaml` dependencies
- [x] **1.2** Create `lib/services/database/migrations/0008_multi_currency.dart`
  - Delete existing 4 seed rows from `currency`; insert all 21 currencies (see spec table with symbols)
  - `ALTER TABLE bankAccount ADD COLUMN currency TEXT NOT NULL DEFAULT 'EUR'`
  - `UPDATE bankAccount SET currency = (SELECT code FROM currency WHERE mainCurrency = 1 LIMIT 1)`
  - `ALTER TABLE bankAccount ADD COLUMN startingValueInMainCurrency REAL NOT NULL DEFAULT 0`
  - `UPDATE bankAccount SET startingValueInMainCurrency = startingValue`
  - `ALTER TABLE transaction ADD COLUMN currency TEXT`
  - `ALTER TABLE transaction ADD COLUMN amountInMainCurrency REAL`
  - `ALTER TABLE transaction ADD COLUMN transferDestinationAmount REAL` (nullable; transfer-only)
  - `ALTER TABLE transaction ADD COLUMN transferEffectiveRate REAL` (nullable; transfer-only)
  - `CREATE TABLE exchange_rate (..., UNIQUE(baseCurrency, targetCurrency, date))`
- [x] **1.3** Register `0008_multi_currency` in `migration_registry.dart`

---

## Phase 2 — Models

- [x] **2.1** Update `lib/model/bank_account.dart`
  - Add `currency` field (`String`, defaults to `'EUR'` in constructor)
  - Add `startingValueInMainCurrency` field (`num`, defaults to `0`)
  - Update `BankAccountFields`, `fromJson()`, `toJson()`, `copy()`
- [x] **2.2** Update `lib/model/transaction.dart`
  - Add `currency` field (`String?`, nullable)
  - Add `amountInMainCurrency` field (`num?`, nullable)
  - Add `transferDestinationAmount` field (`num?`, nullable)
  - Add `transferEffectiveRate` field (`num?`, nullable)
  - Update `TransactionFields`, `fromJson()`, `toJson()`, `copy()`
- [x] **2.3** Create `lib/model/exchange_rate.dart`
  - Fields: `id`, `baseCurrency`, `targetCurrency`, `rate`, `date`, `createdAt`
  - `ExchangeRateFields`, `fromJson()`, `toJson()`, `copy()`

---

## Phase 3 — Repositories

- [x] **3.1** Create `lib/services/database/repositories/exchange_rate_repository.dart`
  - `upsert(ExchangeRate item)` — INSERT OR REPLACE on `(baseCurrency, targetCurrency, date)`
  - `upsertAll(List<ExchangeRate> items)` — batch upsert in a single DB transaction
  - `getLatestRate({required String base, required String target})` — returns most recent row; throws if none
  - `getLatestRateDate({required String base, required String target})` — returns the `date` string of the most recent row; returns `null` if none
  - `getMaxDate()` — `SELECT MAX(date) FROM exchange_rate` for the staleness indicator
- [x] **3.2** Update `lib/services/database/repositories/account_repository.dart`
  - `selectAll()` — no change to per-account `total` (stays native currency)
  - `accountMonthlyBalance()` — stays native (used for the per-account chart)
  - Add `netWorthTotal()` — pure SQL using `SUM(startingValueInMainCurrency) + SUM(COALESCE(amountInMainCurrency, amount))` across all `countNetWorth = 1` accounts; no Dart-side FX conversion needed
  - Add `netWorthMonthlyDeltas()` — monthly income/expense aggregates using `COALESCE(amountInMainCurrency, amount)` for the statistics history chart
- [x] **3.3** Update `lib/services/database/repositories/transactions_repository.dart`
  - `_transactionByFrequencyAndPeriod()` — change `SUM(amount)` to `SUM(COALESCE(amountInMainCurrency, amount))` for income/expense aggregates used in the dashboard and statistics charts
  - `insert()` / `updateItem()` — no change needed (model carries the new fields)

---

## Phase 4 — Network & Exchange Rate Service

- [x] **4.1** Create `lib/services/network/exchange_rate_client.dart`
  - Uses `package:http`
  - `fetchRates(String baseCurrencyCode)` — tries primary CDN endpoint, falls back to pages.dev endpoint on failure; returns `Map<String, double>` of target code → rate, or `null` on total failure
  - Base URL: `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/{base}.json`
  - Fallback: `https://latest.currency-api.pages.dev/v1/currencies/{base}.json`
  - Response parsing: extract `response[baseLower][targetLower]` for each supported target
- [x] **4.2** Create `lib/services/currency/exchange_rate_service.dart`
  - `getRate({required String from, required String to})` — reads from DB via `ExchangeRateRepository`; converts via main currency as intermediate when neither currency is main (`rate(A→main) / rate(B→main)`); throws if any required pair is missing
  - `getRateDate({required String from, required String to})` — returns date string of the most recent cached rate for the pair; returns `null` if none
  - `convertToMain(double amount, String currency)` — shorthand using `getRate(from: currency, to: mainCurrencyCode)`
  - `updateAll()` — calls `ExchangeRateClient.fetchRates(mainCurrencyCode)`, batch-upserts all 21 target pairs; silent no-op on fetch failure

---

## Phase 5 — State Management (Providers)

- [x] **5.1** Create `lib/providers/exchange_rate_provider.dart`
  - `ExchangeRateNotifier` (`@Riverpod(keepAlive: true)`) — wraps `ExchangeRateService`; exposes `getRate()`, `getRateDate()`, `convertToMain()`, `latestRateDate` (async string from `getMaxDate()`)
- [x] **5.2** Update `lib/providers/currency_provider.dart`
  - Rename `CurrencyState` → `CurrencyNotifier` (keep existing `setSelectedCurrency` for simple selection)
  - Add `setMainCurrency(Currency newMain, BuildContext context)`:
    1. Fetch fresh rates for `newMain` (silent skip on failure)
    2. `changeMainCurrency(newMain.id!)` in DB
    3. Batch-update all transaction rows: `amountInMainCurrency = amount × rate(currency → newMain)`, 1:1 fallback for missing rates
    4. Batch-update all account rows: `startingValueInMainCurrency = startingValue × rate(account.currency → newMain)`, 1:1 fallback for missing rates
    5. Call `RestartWidget.restartApp(context)`
  - Replace any startup fallback main currency from USD to EUR (`CurrencyState` + `CurrencyRepository`)
  - Add `hasRatesForCurrency(String code)` — checks if any `exchange_rate` rows exist with `baseCurrency = code`; used by the confirmation dialog to show the no-rates warning
  - Keep confirmation CTA text neutral as `CONFIRM` while warning copy remains explicit
- [x] **5.3** Add `selectedAccountCurrencyProvider` (`@riverpod`) — derives the `currency` code of `selectedBankAccountProvider`; used by the transaction form to know when to show FX info
- [x] **5.4** Update `lib/providers/accounts_provider.dart`
  - `addAccount()` — add required `currency` parameter; call `ExchangeRateService.getRate(from: currency, to: mainCurrency)` to lock `startingValueInMainCurrency = startingValue × rate` (1:1 fallback if no rate cached); pass both to `BankAccount` constructor
  - If account currency differs from main and rate is missing: block save, surface actionable error with inline `Fetch latest rates`
  - After successful fetch, auto-retry save once for the same user action
  - `updateAccount()` — no `currency` or `startingValueInMainCurrency` changes (read-only after creation)
- [x] **5.5** Update `lib/providers/transactions_provider.dart` — `TransactionsNotifier`
  - `create()` — look up source account's `currency`; call `ExchangeRateService.getRate(from: currency, to: mainCurrency)` (or 1:1 if pair missing); set `transaction.currency` and `transaction.amountInMainCurrency`
  - `updateTransaction()` — same FX lookup and lock as `create()`
  - For transfers where source currency ≠ destination currency: keep single-row model and store
    - `amount` as source amount
    - `transferDestinationAmount`
    - `transferEffectiveRate`
    - `amountInMainCurrency` from source-side amount
  - If required FX pair is missing: block save, offer inline `Fetch latest rates`, then auto-retry once
  - On edit, preserve stored transfer FX values by default; recompute toggle deferred (v2.0)
- [x] **5.6** Update `lib/providers/statistics_provider.dart`
  - `updateStatistics()` — replace the Dart-side account total conversion with a call to `AccountRepository.netWorthTotal()` (pure SQL, uses `startingValueInMainCurrency`); the monthly delta query already uses `COALESCE(amountInMainCurrency, amount)` after Phase 3.2. No `ExchangeRateService` call needed at read time.
- [x] **5.7** Update `lib/providers/recurring_transactions_provider.dart`
  - When `populateRecurringTransaction()` creates `Transaction` rows, look up the account's `currency` and call `ExchangeRateService` to set `currency` + `amountInMainCurrency` on each generated row

---

## Phase 6 — UI

- [x] **6.1** Add `RestartWidget` to `lib/main.dart` (or `lib/ui/restart_widget.dart`)
  - Wraps `MaterialApp` with a `UniqueKey`; exposes `static void restartApp(BuildContext context)`
- [x] **6.2** Wire rate-fetch trigger in `main.dart` (after existing recurring-transaction guard)
  ```dart
  final lastRateUpdate = sharedPreferences.getString('last_rate_update');
  if (lastRateUpdate == null ||
      DateTime.now().difference(DateTime.parse(lastRateUpdate)).inDays >= 1) {
    ExchangeRateService.updateAll(); // fire-and-forget
    await sharedPreferences.setString('last_rate_update', DateTime.now().toIso8601String());
  }
  ```
- [x] **6.3** Update `lib/pages/accounts/create_edit_account_page.dart`
  - **Creation mode only:** add a currency picker row (dropdown or bottom sheet) defaulting to main currency; pass selected code to `addAccount()`
  - **Edit mode:** hide the currency picker; show currency as a read-only label ("Currency: USD — cannot be changed after creation")
- [x] **6.4** Update `lib/pages/dashboard/widgets/accounts_sum.dart`
  - Show `account.total` in the account's native currency symbol (from `account.currency`)
  - Add secondary text showing the main-currency equivalent (via `ExchangeRateService.convertToMain()`)
- [x] **6.5** Update `lib/pages/accounts/account_page.dart`
  - Balance header uses native currency symbol (from `account.currency`) instead of `currencyState.symbol`
- [x] **6.6** Update `lib/pages/transactions/create_transaction/create_transaction_page.dart` and `amount_section.dart`
  - When selected account currency ≠ main currency: show rate info line below amount field: *"1 [accountCurrency] = [rate] [mainCurrency] (rate from [date])"* — uses `getRateDate()`
  - For **cross-currency transfers** (source currency ≠ destination currency): reveal a second "Destination amount" field pre-filled from FX; show "using live rate" / "custom rate" badge; reset to live rate when either account changes; retain user override when only amount changes
  - For **same-currency transfers**: single amount field, behaviour unchanged
- [ ] **6.8** Update `lib/ui/widgets/transactions_list.dart` to always show main-currency amount
  - Primary amount: `COALESCE(amountInMainCurrency, amount)` with main currency symbol
  - No native-currency secondary amount in list rows
  - Date group total: computed from main-currency amounts, not native amounts
  - Transfer rows: keep one row; primary amount uses source-side main-currency equivalent
- [ ] **6.10** Update grouped transaction summaries to use locked main-currency amounts
  - `lib/pages/transactions/widgets/panel_list_tile.dart`: category group sums and headers must use `amountInMainCurrency` fallback `amount`
- [ ] **6.9** Add central formatter for account/native symbols and replace ad-hoc symbol usage
  - Create helper in `lib/services/currency/` (e.g. `currency_display_service.dart`) with hardcoded supported-currency display policy
  - USD keeps `$`; ambiguous non-USD currencies display ISO code where needed
  - Replace symbol rendering in account-related UI that currently relies on global main symbol
  - Mandatory audit targets:
    - `lib/pages/dashboard/widgets/accounts_sum.dart`
    - `lib/pages/accounts/account_page.dart`
    - `lib/pages/transactions/create_transaction/widgets/amount_widget.dart`
    - `lib/pages/graphs/widgets/accounts/accounts_card.dart`
    - any account chip/header/summary widget found by grep for `currencyState.symbol` near account totals
- [x] **6.7** Update `lib/pages/settings/general/general_settings_page.dart`
  - Extend existing `CurrencySelectorDialog` flow: before applying the change, show a confirmation dialog
    - Standard message explaining `amountInMainCurrency` recalculation
    - Warning text must explicitly state historical primary amounts in transaction list will be recalculated to the new main currency
    - If `hasRatesForCurrency(newCode)` is false: add warning paragraph about 1:1 fallback
    - On confirm: call `CurrencyNotifier.setMainCurrency(newCurrency, context)` which ends in `RestartWidget.restartApp()`
    - Keep one-step confirmation UX
  - Add staleness row: *"Exchange rates last updated: [date]"* — reads `ExchangeRateNotifier.latestRateDate`; shows "Never" if null

---

## Phase 7 — Demo Data

- [x] **7.1** Update demo data inserts in `lib/services/database/sossoldi_database.dart`
  - `bankAccount` inserts: add `currency` column — keep existing 3 accounts as `'EUR'`, add one `'USD'` account (e.g. "Schwab USD") and one `'GBP'` account (e.g. "Monzo GBP") with realistic starting balances
  - Add demo transactions for the USD and GBP accounts so the multi-currency UI is exercised immediately
  - `currency` inserts: already handled by the migration; remove the 4-row manual seed block from the demo data path to avoid conflicts

---

## Phase 8 — Tests

- [x] **8.1** Unit tests for `ExchangeRateService`
  - `getRate()` returns correct cross-pair rate via main-currency intermediate
  - `getRate()` throws when pair is missing
  - `convertToMain()` returns 1.0 when currency equals main currency
- [x] **8.2** Unit tests for migration `0008`
  - Verify new columns exist after migration
  - Verify 21 currency rows are seeded correctly
  - Verify `bankAccount.currency` is populated from the old main currency
- [x] **8.3** Update existing model tests
  - `BankAccount.fromJson()` / `toJson()` round-trip includes `currency`
  - `Transaction.fromJson()` / `toJson()` round-trip includes nullable `currency` and `amountInMainCurrency`
- [x] **8.4** Widget test: `CreateEditAccountPage` shows currency picker in creation mode and read-only label in edit mode
- [x] **8.5** Widget test: transaction form shows FX rate info row when account currency ≠ main currency
- [ ] **8.6** Onboarding tests
  - New user is forced to pick main currency before continuing
  - Selected main currency is persisted and reused as default for first account and first budget
- [ ] **8.7** Transactions list display tests
  - Row shows main-currency amount as primary value
  - Row does not show native secondary amount
  - Group day total is in main currency
- [ ] **8.8** Account symbol consistency tests
  - Dashboard/account page headers display symbol derived from `account.currency`
  - No account amount widget falls back to global main symbol by mistake
- [ ] **8.9** Missing-rate blocking tests
  - Saving foreign-currency account blocks when no rate exists
  - Saving foreign-currency transaction blocks when no rate exists
  - Inline fetch action auto-retries save once after successful fetch
- [ ] **8.10** Transfer FX persistence tests
  - Transfer stores `transferDestinationAmount` and `transferEffectiveRate`
  - Edit preserves locked transfer FX values by default
  - List primary amount uses source-side main-currency equivalent while totals exclude transfers

---

## Coverage Checklist (Release Gate)

- [ ] Onboarding: main currency required before first account/budget flow
- [ ] Transactions list: main-currency primary amount verified on mixed-currency data
- [ ] Account totals: all screens audited to use account symbol
- [ ] Settings main-currency change: transaction list refreshes and still shows primary main-currency values
- [ ] Regression pass: existing single-currency users see unchanged behavior

---

## Open Questions

> Clear these before implementation starts.

- [x] **Q1** — ~~Should the demo/fake data include at least one non-EUR bank account?~~ → **Yes: add a USD and a GBP demo account alongside the existing EUR ones**
- [x] **Q2** — ~~Mixed rate snapshots in net worth history chart~~ → **Resolved: `startingValueInMainCurrency` is locked at account creation time, so both the starting point and all transaction deltas use locked amounts. The net worth query is pure SQL, no live rate involved at read time. The chart is fully internally consistent.**

