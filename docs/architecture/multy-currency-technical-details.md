## Database Schema

### Changes to existing tables

#### `bankAccount`

Two new columns added:

| Column | Type | Notes |
|--------|------|-------|
| `currency` | TEXT NOT NULL DEFAULT `'EUR'` | ISO 4217 code of the account's native currency. Migration sets this to the main currency code for all existing rows. |
| `startingValueInMainCurrency` | REAL NOT NULL DEFAULT `0` | `startingValue` converted to the main currency, locked at account creation time. Migration sets this equal to `startingValue` for all existing rows (which are implicitly in the main currency). |

#### `transaction`

Two new nullable columns added:

| Column | Type | Notes |
|--------|------|-------|
| `currency` | TEXT | ISO 4217 code of the account at the time of the transaction. `NULL` for pre-feature transactions — treated as main currency in all queries. |
| `amountInMainCurrency` | REAL | `amount` converted to the main currency, locked at save time. `NULL` for pre-feature transactions — treated as equal to `amount` via `COALESCE`. |

All aggregate SQL uses `COALESCE(amountInMainCurrency, amount)` so existing data continues to work correctly without a back-fill migration.

### New table: `exchange_rate`

Stores one rate per ordered currency pair per date. The base currency is always the app's main currency; only main-currency → each supported currency pairs are stored. Converting between two non-main currencies is done via the main currency as an intermediate.

| Column | Type | Notes |
|--------|------|-------|
| `id` | INTEGER PK | |
| `baseCurrency` | TEXT NOT NULL | ISO 4217 (e.g. `"EUR"`) |
| `targetCurrency` | TEXT NOT NULL | ISO 4217 (e.g. `"USD"`) |
| `rate` | REAL NOT NULL | Units of `targetCurrency` per 1 unit of `baseCurrency` |
| `date` | TEXT NOT NULL | `YYYY-MM-DD` of the rate |
| `createdAt` | TEXT NOT NULL | |

**Unique constraint:** `(baseCurrency, targetCurrency, date)` — upsert on conflict.

---

## Architecture

### Network Layer

New file: `lib/services/network/exchange_rate_client.dart`

- HTTP client: **`package:http`**
- API: [fawazahmed0/exchange-api](https://github.com/fawazahmed0/exchange-api)
  - Primary endpoint: `https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/{base_lower}.json`
  - Fallback endpoint: `https://latest.currency-api.pages.dev/v1/currencies/{base_lower}.json`
  - Response shape: `{ "date": "YYYY-MM-DD", "{base}": { "{target}": rate, ... } }`
- On a successful fetch: batch-upsert all supported target pairs for the main currency into `exchange_rate`
- **Failure handling:** silent skip. The last cached rate remains in the DB. `last_rate_update` in `SharedPreferences` is not updated on failure, keeping the staleness indicator accurate.

> **Known risk:** The exchange-rate API is a free community project with no SLA. If it becomes unreliable, migration to a paid provider (e.g. Open Exchange Rates, Fixer.io) should be considered.

### Rate Update Trigger (`main.dart`)

Follows the same once-per-day guard as recurring transactions:

```dart
// In main.dart — mirrors the existing recurring-transaction guard pattern
final lastRateUpdate = sharedPreferences.getString('last_rate_update');
if (lastRateUpdate == null ||
    DateTime.now().difference(DateTime.parse(lastRateUpdate)).inDays >= 1) {
  // Fire-and-forget; key is written regardless of success so we don't retry
  // on the same day. The Settings staleness indicator reads MAX(date) from
  // the exchange_rate table and only advances on a successful upsert.
  ExchangeRateService.updateAll();
  await sharedPreferences.setString(
    'last_rate_update',
    DateTime.now().toIso8601String(),
  );
}
```

Does not block app startup. UI shows last-known values immediately.

### FX Conversion Helper

`lib/services/currency/exchange_rate_service.dart` exposes:

```dart
/// Returns the most recent cached rate from [from] to [to].
/// Throws if no rate has ever been cached for this pair.
Future<double> getRate({required String from, required String to});

/// Returns the date of the most recently cached rate for [from] → [to].
/// Used by the transaction form to display rate age to the user.
Future<String?> getRateDate({required String from, required String to});

/// Shorthand: converts [amount] in [currency] to the current main currency.
Future<double> convertToMain(double amount, String currency);

/// Batch-fetches fresh rates from the API and upserts into the DB.
Future<void> updateAll();
```

### Transaction Save Flow

Every time a transaction is created or edited:

1. Look up the source account's `currency`
2. Call `getRate(from: accountCurrency, to: mainCurrency)` — reads from the local DB, no network call at save time
3. Persist `currency = accountCurrency` and `amountInMainCurrency = amount × rate` on the transaction row

### Onboarding and Defaults Flow

1. On first app launch (before account or budget creation), show a required main-currency selection step
2. Default selection is inferred from locale when possible; user can change it explicitly
3. On confirmation:
  - Set `currency.mainCurrency`
  - Use selected currency as default for first account creation
  - Use selected currency as baseline for budget creation and evaluation
4. If onboarding is resumed later, the step remains blocking until main currency is selected

### Transaction List Display Rules

1. Every transaction tile computes display amount as `COALESCE(amountInMainCurrency, amount)` and renders it with the main currency symbol
2. If the transaction native currency differs from main currency, render a secondary line with native amount and native symbol/code
3. Transfer rows follow the same rule for the visible side of each row: main currency amount is primary, native amount is secondary when different
4. Date-group daily totals in the transactions list are also computed and rendered in main currency

### Cross-Currency Transfer Flow

1. User selects source account (currency A) and destination account (currency B)
2. User enters source amount
3. If A ≠ B: app fetches the A→B rate from the local cache and reveals a second destination amount field, pre-filled as `destinationAmount = sourceAmount × rate(A→B)` (computed as `rate(A→main) / rate(B→main)`). If A = B: no second field is shown and both sides use the same amount as today.
4. User may override `destinationAmount` (the field is editable with a clear "using live rate" / "custom rate" indicator)
   - The override is **sticky** until either the source account or destination account changes, at which point the indicator resets to "using live rate" and the destination amount is recalculated from the new rate context
5. Two transaction rows are written atomically in a single SQLite DB transaction:
   - `TRSF` debit on source: `amount = sourceAmount`, `currency = A`, `amountInMainCurrency = sourceAmount × rate(A→main)`
   - `TRSF` credit on destination: `amount = destinationAmount`, `currency = B`, `amountInMainCurrency = destinationAmount × rate(B→main)`

### Main Currency Change Flow

1. User selects a new main currency in Settings
2. App shows a confirmation dialog explaining:
   - All `amountInMainCurrency` values on past transactions will be recalculated
   - The calculation uses the most recently cached rates for the new main currency
   - Historical accuracy is best-effort (no time-series rates are stored for old main currencies)
   - **If no rates are cached for the new main currency** (empty `exchange_rate` table or missing pairs): the dialog additionally warns *"No exchange rates are available for [currency]. Any existing transactions will have their converted amounts set to their original amount until rates are fetched. Connect to the internet to fetch rates."* The user may still proceed.
3. On confirmation:
   a. Fetch fresh rates for the new main currency if online (silent skip if offline)
   b. Update `currency.mainCurrency` flags in the DB (set old main → 0, new main → 1)
   c. Batch-update every transaction row: `amountInMainCurrency = amount × rate(transactionCurrency → newMain)`; for rows where `currency IS NULL`, treat `currency` as the old main currency code. For any pair with no cached rate, set `amountInMainCurrency = amount` (1:1 fallback — will self-correct once rates are fetched)
   d. Batch-update every account row: `startingValueInMainCurrency = startingValue × rate(account.currency → newMain)`; same 1:1 fallback for missing rates
   e. Account `currency` fields are **not** changed — accounts keep their own native currency regardless of the main currency setting
4. Trigger a full app restart by calling `RestartWidget.restartApp(context)` on the root widget (a `RestartWidget` wraps `MaterialApp` and swaps it via a `UniqueKey`, rebuilding the entire provider graph cleanly)

### Net Worth / Statistics Queries

All aggregate SQL that previously summed `amount` now sums `COALESCE(amountInMainCurrency, amount)` to handle both new and pre-feature transactions:

```sql
-- Total net worth across all active accounts (pure SQL, no Dart-side FX conversion needed)
-- The subquery aggregates per account (GROUP BY b.id) so that startingValueInMainCurrency
-- is counted once per account, not once per transaction row.
SELECT COALESCE(SUM(account_total), 0) AS total
FROM (
  SELECT
    b.startingValueInMainCurrency
    + COALESCE(SUM(CASE
        WHEN t.type = 'IN'
          OR (t.type = 'TRSF' AND t.idBankAccountTransfer = b.id)
          THEN COALESCE(t.amountInMainCurrency, t.amount)
        WHEN t.type = 'OUT'
          OR (t.type = 'TRSF' AND t.idBankAccount = b.id)
          THEN -COALESCE(t.amountInMainCurrency, t.amount)
        ELSE 0
      END), 0) AS account_total
  FROM bankAccount b
  LEFT JOIN `transaction` t ON t.idBankAccount = b.id OR t.idBankAccountTransfer = b.id
  WHERE b.active = 1 AND b.countNetWorth = 1 AND b.deletedAt IS NULL
  GROUP BY b.id, b.startingValueInMainCurrency
)
```

The per-account `total` in `selectAll()` continues to use `amount` (native currency) for the per-account balance display. A separate query drives the dashboard net worth card and statistics chart.

> **Note:** Both `startingValueInMainCurrency` (locked at account creation) and `amountInMainCurrency` (locked at transaction save) use the same snapshot principle. The net worth query is therefore pure SQL — no Dart-side FX conversion at read time. The statistics history chart walks backwards from today's locked net worth using `COALESCE(amountInMainCurrency, amount)` deltas; both the starting point and the deltas are locked amounts, making the chart fully internally consistent.

### State Management

Follows existing Riverpod + code-generation patterns:

- `CurrencyNotifier` (`@Riverpod(keepAlive: true)`) — CRUD on the `currency` table; exposes `mainCurrency` stream and `setMainCurrency()` which triggers the recalculation flow
- `ExchangeRateNotifier` (`@Riverpod(keepAlive: true)`) — wraps `ExchangeRateService`; exposes `getRate()` and `lastUpdatedAt`
- `SelectedAccountCurrencyProvider` — currency of the currently selected account (drives the transaction entry form FX display)

### Database Migration

New migration file: `lib/services/database/migrations/0008_multi_currency.dart`

1. Delete existing 4 seed rows from `currency` table; insert the full 21-currency list
2. `ALTER TABLE bankAccount ADD COLUMN currency TEXT NOT NULL DEFAULT 'EUR'`
3. `UPDATE bankAccount SET currency = (SELECT code FROM currency WHERE mainCurrency = 1 LIMIT 1)`
4. `ALTER TABLE bankAccount ADD COLUMN startingValueInMainCurrency REAL NOT NULL DEFAULT 0`
5. `UPDATE bankAccount SET startingValueInMainCurrency = startingValue` (existing accounts are implicitly in the main currency)
6. `ALTER TABLE transaction ADD COLUMN currency TEXT`
7. `ALTER TABLE transaction ADD COLUMN amountInMainCurrency REAL`
8. `CREATE TABLE exchange_rate (id INTEGER PRIMARY KEY AUTOINCREMENT, baseCurrency TEXT NOT NULL, targetCurrency TEXT NOT NULL, rate REAL NOT NULL, date TEXT NOT NULL, createdAt TEXT NOT NULL, UNIQUE(baseCurrency, targetCurrency, date))`

---

## Open Questions

- ~~Exact symbol strings for the ~20 currencies~~ → **resolved: JPY = `¥`, CNY = `元`; ZAR dropped; KRW (`₩`) added; full symbol list in the Supported Currencies table**
- ~~UX placement for the per-account currency picker~~ → **resolved: account creation screen only; currency is read-only after creation**
- ~~Whether `startingValue` is in the account's native currency~~ → **resolved: yes, always in the account's native currency. A companion column `startingValueInMainCurrency` is locked at account creation time and used in all net worth SQL queries — no Dart-side conversion needed at read time**
- ~~Whether the Settings screen staleness indicator shows a formatted date or a relative "X days ago" string~~ → **resolved: show formatted date (e.g. "28 May 2026"), reading `MAX(date)` from `exchange_rate` table**

---

## Related

- [Roadmap](../roadmap.md)
- [Asset Tracking spec](asset-tracking.md) (this feature is a listed pre-requisite for Asset Tracking v2.0)
