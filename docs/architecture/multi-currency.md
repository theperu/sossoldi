# Feature Spec: Multi-Currency Support

**Status:** Draft  
**Priority:** High  
**Estimated Effort:** Large  
**Target Release:** v1.5 (pre-requisite for Asset Tracking v2.0)  
**Author:** @theperu  
**Created:** 31/05/2026  
**Last Updated:** 05/07/2026

---

## Overview

This feature enables users to assign individual currencies to each bank account and have all transactions, balances, and net worth figures automatically converted to a single user-selected main currency for display. Main currency is selected during onboarding so new users start with correct defaults for budgets, account setup, and transaction display. Exchange rates are fetched once daily from the free, open-source [exchange-rate API](https://github.com/fawazahmed0/exchange-api) and cached in the local database. The system is transparent and offline-safe — stale cached rates are used silently if the device has no internet.

## Problem Statement

Currently, every bank account and transaction is implicitly stored in a single currency (no currency field exists on accounts or transactions). Users who hold money in multiple currencies cannot accurately track their net worth or manage their finances. This also blocks the Asset Tracking feature, which requires multi-currency infrastructure for asset valuations.

---

## User Story

> As a user who holds money in multiple currencies,  
> I want to assign a currency to each of my bank accounts,  
> so that my balances are shown in the correct currency and my total net worth is automatically converted to my preferred main currency.

### Scenarios

**Scenario 1 — Expat Worker**  
Anna lives in Switzerland (CHF salary) but keeps savings in EUR and GBP. She sets EUR as her main currency, creates a CHF account and a GBP account. All balances show in their native currency; the dashboard and net worth chart convert everything to EUR. Expected outcome: Anna can see her total EUR-equivalent net worth and monitor how FX fluctuations affect her wealth.

**Scenario 2 — Investor**  
Marco's main currency is EUR. He opens a USD brokerage account. When he records a USD income transaction, the app locks the EUR equivalent at today's rate. Six months later the rate has moved, but his old transactions still show the originally-locked EUR value, preserving a reliable historical record. Expected outcome: no retroactive distortion of past figures.

**Scenario 3 — Traveller**  
Sofia is travelling and briefly holds a JPY cash account alongside her EUR current account. She transfers €200 from EUR to JPY. The app computes and stores the JPY equivalent using the current cached EUR/JPY rate and records the effective rate. Expected outcome: both accounts are correctly debited and credited at the cached rate.

---

## Acceptance Criteria

**Core:**
- Onboarding includes a required "Main currency" step before users can create their first account or budget
- Users can select a currency for each bank account at creation time (default: the current main currency)
- Users can select a main/display currency for the whole app
- Account balances are shown in the account's native currency, with the main-currency equivalent as secondary text
- Every UI that shows an account amount uses that account's own currency symbol (never a global symbol fallback)
- All aggregate totals (net worth, statistics, dashboard liquidity) are displayed in the main currency
- Changing the main currency shows a confirmation dialog, then recalculates all locked `amountInMainCurrency` values using the most recently cached rates

**Exchange Rates:**
- Rates are fetched once per day on app open (same guard pattern as recurring transactions)
- The most recent fetched rate for each supported pair is saved in a new `exchange_rate` table
- If the fetch fails (offline or API error), the last cached rate is used silently

**Transaction FX:**
- Every new or edited transaction stores both `amount` (native account currency) and `amountInMainCurrency` (converted and locked at save time)
- Transaction list rows always show `amountInMainCurrency` in the current main currency (primary value)
- Transaction list rows also show the native transaction amount as secondary text when `currency != mainCurrency` to preserve source-currency context
- The transaction form shows the rate age next to the converted amount whenever the account currency differs from the main currency (e.g. *"1 EUR = 108 JPY (rate from 3 days ago)"*). This is always visible, not just when stale, so the user is always informed of the rate freshness
- Cross-currency transfers: the app pre-fills the destination amount using the current cached FX rate; the user can override it manually

**Recurring Transactions:**
- Each recurrence fires using the most recently cached exchange rate at the time it fires

**Budget:**
- Budgets are defined and evaluated in the main currency only
- Foreign-currency spending is converted to main currency using the locked `amountInMainCurrency` stored on each transaction

**Historical Net Worth Chart:**
- Uses the locked `amountInMainCurrency` summed across transactions per month

---

## Out of Scope (v1.5)

- Re-locking `amountInMainCurrency` on transactions saved with stale rates (deferred; no `rateDate` column on `transaction`)
- Forward FX contracts / hedging
- Per-transaction manual currency override (currency always inherits from the account)
- Currency conversion fee / spread tracking
- Cryptocurrency as a currency (handled separately under Asset Tracking as `DIGITAL_ASSET`)
- FX rate alerts / notifications
- Background rate updates via `workmanager` (deferred to v2.0, same as Asset Tracking)

---

## Supported Currencies

~20 major world currencies, hard-coded in the migration. Replaces and extends the existing 4-currency seed in `0001_initial_schema.dart`.

| Code | Symbol | Name |
|------|--------|------|
| `EUR` | `€` | Euro |
| `USD` | `$` | United States Dollar |
| `GBP` | `£` | British Pound Sterling |
| `CHF` | `CHF` | Swiss Franc |
| `CAD` | `C$` | Canadian Dollar |
| `AUD` | `A$` | Australian Dollar |
| `NZD` | `NZ$` | New Zealand Dollar |
| `SEK` | `kr` | Swedish Krona |
| `NOK` | `kr` | Norwegian Krone |
| `DKK` | `kr` | Danish Krone |
| `PLN` | `zł` | Polish Zloty |
| `CZK` | `Kč` | Czech Koruna |
| `HUF` | `Ft` | Hungarian Forint |
| `BRL` | `R$` | Brazilian Real |
| `MXN` | `MX$` | Mexican Peso |
| `JPY` | `¥` | Japanese Yen |
| `CNY` | `元` | Chinese Renminbi |
| `HKD` | `HK$` | Hong Kong Dollar |
| `SGD` | `S$` | Singapore Dollar |
| `INR` | `₹` | Indian Rupee |
| `KRW` | `₩` | South Korean Won |

The existing `currency` table schema is unchanged; the migration replaces the 4 existing seed rows with this full list.