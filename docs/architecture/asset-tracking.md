# Feature Spec: Asset Tracking

**Status:** Draft  
**Priority:** High  
**Estimated Effort:** Large  
**Target Release:** v2.0  
**Author:** @theperu  
**Created:** 10/09/2025  
**Last Updated:** 30/05/2026

---

## Overview

This feature enables users to track all their assets in one centralised place within the app. Users can manage investments (stocks, bonds, ETFs, crypto), real estate properties, vehicles, collectibles, private equity, and other valuable assets. Where possible, asset prices are automatically updated once daily to provide up-to-date portfolio valuation.

## Problem Statement

Currently, users can only track a subset of their net worth (bank accounts and transactions). This prevents users from getting a complete picture of their financial situation. With this feature, users will be able to track their entire net worth — including all asset classes — in one unified platform, eliminating the need for multiple apps or spreadsheets.

---

## User Story

> As a user who owns various assets,  
> I want to track all my investments, properties, vehicles, and collectibles in one place,  
> so that I can see my complete net worth, monitor asset performance over time, and understand my asset allocation.

### Scenarios

**Scenario 1 — Young Investor**  
Sofia has started investing: €2,000 in stocks, €500 in crypto, and saved €3,000 for art supplies. She adds her investments as assets with purchase prices and dates. The app automatically updates stock/crypto prices on app open. Expected outcome: Sofia sees her total net worth (savings + bank accounts + investments) and tracks how her investments grow over time.

**Scenario 2 — Collector**  
Marco owns a valuable wine collection (€5,000), vintage watch (€3,000), and his car (€15,000). He adds each item as an asset with the current estimated values and manually updates valuations when appraised. Expected outcome: Marco can see his collectibles as part of his total net worth and track appreciation alongside his dining expenses.

**Scenario 3 — Diverse Portfolio**  
Giovanni has freelance savings in multiple accounts (€20,000), stocks/ETFs (€15,000), crypto (€3,000), owns his apartment (€200,000), a car (€10,000), and business equipment (€5,000). He tracks all assets in the app, with automatic price updates for investments, and views an asset allocation chart. Expected outcome: Giovanni gets a complete picture of his net worth and makes informed decisions about rebalancing his portfolio.

---

## Acceptance Criteria

**Core:**
- Users can create, view, edit, and delete assets
- Support for all asset categories (see Asset Types below)
- Asset values are included in total net worth calculation
- Users can manually update asset values

**Automatic Price Updates:**
- Display "last updated" timestamp per asset
- Prices updated on app open (once per day, guarded by `SharedPreferences` date check)
- Manual value update available for all assets

**Performance Tracking:**
- Show gross gain/loss per asset: `(currentPricePerUnit − avgPurchasePrice) × quantity`
- Show net gain/loss per asset: `grossGain × (1 − taxRate / 100)` (when `taxRate` is set)
- Performance percentage per asset
- Historical value chart per asset (from `asset_value_history`)
- Total portfolio performance metrics

**Asset Allocation:**
- Pie chart showing % distribution across asset categories

**Documentation:**
- Notes/description field per asset

**Standard:**
- iOS and Android support
- Dark mode support

---

## Out of Scope (v2.0)

- Tax calculation and reporting (storing `taxRate` is for net gain *display* only — not filing)
- Automatic broker account synchronisation (Plaid or similar)
- Pension/retirement account tracking
- Insurance policies as assets
- Liabilities/loans tracking — deferred to v2.1
- Options/derivatives — deferred to v2.1 (expiry, non-linear pricing, contract sizing require dedicated support)
- Lot-based cost basis tracking — deferred to v2.1
- Background price updates via `workmanager`

---

## Pre-requisites

**Multi-currency support must ship before this feature.** Asset Tracking relies on the multi-currency infrastructure for storing and displaying asset values in their native currency and converting to the user's display currency.

---

## Asset Types

Hard-coded Dart enum (same pattern as `TransactionType`). The enum carries an `isAutoUpdateSupported` getter that gates price-fetch logic.

| Code | Label | Auto-update | Source |
|------|-------|-------------|--------|
| `STOCK` | Stocks | ✅ | Yahoo Finance |
| `ETF` | ETFs | ✅ | Yahoo Finance |
| `MUTUAL_FUND` | Mutual Funds | ✅ | Yahoo Finance |
| `BOND` | Bonds | ✅ | Yahoo Finance |
| `DIGITAL_ASSET` | Digital Assets | ✅ | CoinGecko |
| `REAL_ESTATE` | Real Estate | ❌ | Manual |
| `PRIVATE_INVESTMENT` | Private Investments | ❌ | Manual |
| `COLLECTIBLE` | Collectibles & Physical Assets | ❌ | Manual |
| `OTHERS` | Others | ❌ | Manual |

---

## Database Schema

Three new tables. All follow the existing `BaseEntity` conventions (`createdAt`, `updatedAt`; soft delete via `deletedAt` where applicable).

### `asset`

| Column | Type | Notes |
|--------|------|-------|
| `id` | INTEGER PK | |
| `name` | TEXT NOT NULL | User-defined label (e.g. "Apple Inc.", "Milan Apartment") |
| `type` | TEXT NOT NULL | Enum code (see Asset Types) |
| `ticker` | TEXT | Nullable. Null = manual-only asset. Populated from search at creation. |
| `currency` | TEXT NOT NULL | ISO 4217 code (e.g. `"USD"`, `"EUR"`). From multi-currency feature. |
| `quantity` | REAL NOT NULL | Default `1` for non-quantity assets. Updated incrementally on each trade (see Trade Model). |
| `avgPurchasePrice` | REAL | Nullable. Per unit. Updated incrementally on each BUY/IMPORT; unchanged on SELL (see Trade Model). |
| `currentValue` | REAL NOT NULL | Total value in asset currency. Kept current by API fetch or manual update. |
| `taxRate` | REAL | Nullable. 0–100 %. Used only to compute net gain display. |
| `note` | TEXT | Nullable. Free-text description. |
| `lastValueUpdatedAt` | TEXT | Datetime of last `currentValue` update. Shown in UI as staleness indicator. |
| `position` | INTEGER NOT NULL | For user-controlled reordering (same pattern as `BankAccount`). |
| `createdAt` | TEXT NOT NULL | |
| `updatedAt` | TEXT NOT NULL | |
| `deletedAt` | TEXT | Soft delete. Set when user explicitly removes an asset. Linked transactions are preserved for account balance integrity. |

### `transaction` table extensions

No separate `asset_movement` table. All asset trades are stored in the existing `transaction` table via three new `TransactionType` values:

| Dart enum | Wire code | `idBankAccount` | Visible in transaction list | Account balance impact |
|-----------|-----------|-----------------|-----------------------------|-----------------------|
| `assetBuy` | `"ASSET_BUY"` | Required (source account) | ✅ Yes | Decreases (money out) |
| `assetSell` | `"ASSET_SELL"` | Required (destination account) | ✅ Yes | Increases (money in) |
| `assetImport` | `"ASSET_IMPORT"` | `null` (no money flow) | ❌ Hidden | None |

**Four nullable columns added to `transaction`:**

| Column | Type | Notes |
|--------|------|-------|
| `idAsset` | INTEGER | FK → `asset.id`. Null for non-asset transactions. |
| `assetName` | TEXT | Denormalized asset name (like `categoryName`). Null for non-asset transactions. |
| `quantity` | REAL | Units bought/sold/imported. Null for non-asset transactions. |
| `pricePerUnit` | REAL | Price per unit at time of trade. Null for non-asset transactions. |

**`idBankAccount` nullability:** currently non-nullable in the Dart model (`as int`). Must be changed to `int?`. Only `ASSET_IMPORT` transactions have a null `idBankAccount`; because all account balance SQL uses an inner JOIN on `idBankAccount`, imports are automatically excluded from account totals with no extra SQL changes.

**`amount` field:**
- `ASSET_BUY`/`ASSET_SELL`: `quantity × pricePerUnit` (real money flow)
- `ASSET_IMPORT`: `quantity × pricePerUnit` (informational; no money flow)

**After every `ASSET_BUY`/`ASSET_SELL`/`ASSET_IMPORT` write,** `asset.quantity` and `asset.avgPurchasePrice` are updated incrementally:
- **BUY / IMPORT:** `new_qty = old_qty + trade_qty`; `new_avg = (old_qty × old_avg + trade_qty × price) / new_qty`
- **SELL:** `new_qty = old_qty − sold_qty`; `avgPurchasePrice` unchanged

If a past trade is **deleted or edited** from the asset detail screen, a full recompute from the transaction log is triggered for that asset (exceptional path only).

**Budget impact:** automatically excluded — budgets join on `idCategory` which is null for asset transactions.

**Transaction list filtering:** the transactions list query adds `WHERE type NOT IN ('ASSET_IMPORT')`. Tapping an `ASSET_BUY`/`ASSET_SELL` row navigates to the asset detail screen (read-only from the transaction screen).

### `asset_value_history`

Stores point-in-time total value snapshots for historical charting. Written in two cases:
1. On any `currentValue` update (API fetch or manual revaluation) — immediate row
2. On app open — if the current month is ahead of the last recorded month, write a month-end snapshot for the previous month

| Column | Type | Notes |
|--------|------|-------|
| `id` | INTEGER PK | |
| `idAsset` | INTEGER NOT NULL | FK → `asset.id` |
| `value` | REAL NOT NULL | Total value in asset currency at this point |
| `date` | TEXT NOT NULL | Snapshot date |
| `createdAt` | TEXT NOT NULL | |

---

## Architecture

### Network Layer

New package: `lib/services/network/`

- HTTP client: **`dio`** (interceptors and retry support needed for multi-currency FX in future)
- Two clients: `YahooFinanceClient` and `CoinGeckoClient`
- **Failure handling:** silent skip. `Asset.currentValue` stays at last known value. `lastValueUpdatedAt` is not updated, making staleness visible in the UI. No error alert shown to the user.

> **Known risk:** Yahoo Finance is an unofficial API with no SLA. It has broken without warning historically. This is a documented risk; if it becomes unreliable, migration to a paid provider (e.g. Financial Modeling Prep) should be considered.

### Price Update Trigger (`main.dart`)

Follows the existing recurring-transactions check pattern:

```dart
// In main.dart, fire-and-forget (unawaited)
final lastPriceUpdate = sharedPreferences.getString('last_price_update');
if (lastPriceUpdate == null ||
    DateTime.now().difference(DateTime.parse(lastPriceUpdate)).inDays >= 1) {
  unawaited(PriceUpdateService.updateAll());
  await sharedPreferences.setString(
    'last_price_update',
    DateTime.now().toIso8601String(),
  );
}
```

Does not block app startup. UI shows last-known values immediately; Riverpod providers refresh when the background fetch completes.

### Asset Creation Flow

Three distinct paths, depending on the user's intent:

**Path 1 — Pre-existing asset ("I already own this"):**
1. User selects asset type and optionally searches for a ticker
2. User enters `quantity` and optionally `avgPurchasePrice`; no source account selected
3. Writes one `ASSET_IMPORT` transaction (`idBankAccount = null`, `amount = quantity × pricePerUnit`)
4. `asset.quantity` and `asset.avgPurchasePrice` recomputed from transaction log
5. First `asset_value_history` row written

**Path 2 — New purchase ("I'm buying this now"):**
1. User selects asset type; optionally searches for a ticker (auto-update types)
2. User selects a source bank account (required)
3. User enters `quantity` and `pricePerUnit`
4. Writes one `ASSET_BUY` transaction (debits source account)
5. `asset.quantity` and `asset.avgPurchasePrice` recomputed; `asset_value_history` row written
6. Both writes are wrapped in a single SQLite DB transaction for atomicity

**Path 3 — Sell:**
1. From the asset detail screen, user taps "Sell"
2. User selects a destination bank account (required)
3. User enters `quantity` and `pricePerUnit`
4. Writes one `ASSET_SELL` transaction (credits destination account)
5. `asset.quantity` recomputed; if `quantity == 0`, asset is soft-deleted (`deletedAt` set)
6. `asset_value_history` row written; both writes are atomic

### Net Worth Integration

The `Statistics` provider's historical net worth chart is extended (Option B):

- For each month M on the chart: `netWorth(M) = accountBalance(M) + sum(asset_value_history WHERE month = M)`
- Asset contribution for months before an asset existed = 0 (correct)
- `Asset.currentValue` (summed across all active assets) is added to the current-month total

**SQL correctness fixes required in `account_repository.dart`:**

The existing `account.total` SQL uses a blanket `ELSE -amount` for all non-`IN`/non-`TRSF` types. `ASSET_SELL` must be moved to the income branch:

```sql
-- Before (broken for ASSET_SELL):
CASE WHEN type = 'IN' OR (type = 'TRSF' AND idBankAccountTransfer = b.id)
  THEN amount ELSE -amount END

-- After (explicit, safe for future types):
CASE
  WHEN type IN ('IN', 'ASSET_SELL')
    OR (type = 'TRSF' AND idBankAccountTransfer = b.id) THEN amount
  WHEN type IN ('OUT', 'ASSET_BUY')
    OR (type = 'TRSF' AND idBankAccount = b.id)        THEN -amount
  ELSE 0
END
```

The same explicit pattern must be applied to `accountDailyBalance` and `accountMonthlyBalance` queries, and to the new historical net worth chart query.

### State Management

Follows existing Riverpod + code-generation patterns:

- `AssetsNotifier` (`@Riverpod(keepAlive: true)`) — CRUD + reorder
- `AssetTradesNotifier` — per-asset trade history (queries `transaction WHERE idAsset = X AND type IN ('ASSET_BUY', 'ASSET_SELL', 'ASSET_IMPORT')`)
- `AssetValueHistoryNotifier` — per-asset history for chart
- `SelectedAssetProvider` — currently selected asset for detail/edit screens

### Database Migration

New migration file: `lib/services/database/migrations/000X_asset_tracking.dart`

1. Create `asset` table
2. Create `asset_value_history` table
3. `ALTER TABLE transaction ADD COLUMN idAsset INTEGER`
4. `ALTER TABLE transaction ADD COLUMN assetName TEXT`
5. `ALTER TABLE transaction ADD COLUMN quantity REAL`
6. `ALTER TABLE transaction ADD COLUMN pricePerUnit REAL`
7. Update Dart model: `idBankAccount` changed from `required int` → `int?`; `fromJson` cast changed from `as int` → `as int?`

---

## Open Questions

- Navigation placement — deferred to UI redesign
- Exact Yahoo Finance and CoinGecko search/quote endpoints to use (validate during implementation)
- Fallback strategy if Yahoo Finance breaks in production

---

## Related

- [Roadmap](../roadmap.md)
- Multi-currency feature spec (pre-requisite, TBD)
