# UZee — Data Model

| | |
|---|---|
| Version | 0.1 (2026-10-06) |
| Status | Draft — awaiting user review |
| Schema | `v1_baseline` (GRDB migration id) |
| Companion | [ARCHITECTURE.md](ARCHITECTURE.md) |

SQLite via GRDB. Swift types are UZeeCore domain types; GRDB record types in UZeeData map 1:1 to the tables below. PRD requirement IDs are in §9.

---

## 1. Conventions

| Rule | Detail |
|---|---|
| Ids | `id TEXT PRIMARY KEY`, canonical uppercase UUID string generated in Swift (`UUID().uuidString`). Readable in debugging, equals the future CloudKit `recordName`. SQLite rowid is never used. |
| Foreign keys | `*_id TEXT` referencing a UUID; `PRAGMA foreign_keys = ON`. |
| Timestamps | `Date` ↔ `INTEGER` Unix epoch **milliseconds, UTC**. |
| Calendar dates | Dates without time (due dates, budget periods, a transaction's day) are `LocalDate` ↔ `TEXT 'YYYY-MM-DD'`, the user's local day. They never shift when the time zone changes (CAL-07). |
| Money | `Int64` minor units ↔ `INTEGER` (`*_minor`) + `currency_code TEXT` (ISO 4217). PKR and USD both have 2 minor units, so Rs 14,517 = `1451700`, $2.99 = `299`. Never `Double`/`REAL`. |
| Rates | `Decimal` ↔ `TEXT` canonical decimal string ("280", "278.70"), meaning **base-currency units per 1 unit** of the foreign currency. Stored as text so no float conversion happens. |
| Ratios | Percentages as basis points `Int` (10000 = 100%); share weights as `Int`. |
| Enums | Swift `String` raw-value enums ↔ `TEXT`. **No SQL CHECK on enum values**, so adding a case is code-only (additive) and a row written by a newer app version decodes to `.unknown` instead of failing. |
| Booleans | `Bool` ↔ `INTEGER` 0/1 with `CHECK (x IN (0,1))`. |
| Names | Table names singular snake_case. `txn` (not `transaction`) and `split_group` (not `group`) avoid SQL keywords. |
| Text normalisation | `*_key` columns = lowercased, trimmed, diacritics folded, inner whitespace collapsed; used for uniqueness and matching. |

### Standard columns (marked **S** below) on every synced table

| Column | Swift | SQL | Req | Default | Notes |
|---|---|---|---|---|---|
| id | `UUID` | TEXT PK | ✓ | new UUID | Immutable |
| owner_id | `UUID` | TEXT | ✓ | Settings.owner_id | Household/owner scope (PRD §18); one value in v1 |
| created_at | `Date` | INTEGER | ✓ | now | Immutable |
| updated_at | `Date` | INTEGER | ✓ | now | Set by repository on every write; sync LWW key |
| deleted_at | `Date?` | INTEGER | – | NULL | Soft delete; non-NULL = in Recently Deleted |
| deletion_batch_id | `UUID?` | TEXT | – | NULL | Shared by every row soft-deleted in one user action, so restore brings back exactly that set |
| is_sample | `Bool` | INTEGER | ✓ | 0 | DATA-04 / PRV-04 |

All "unique" constraints below are **partial unique indexes `WHERE deleted_at IS NULL`** unless noted, so a deleted name can be reused and later restored only if no live clash exists (restore asks to rename otherwise). Every list query filters `deleted_at IS NULL`; indexes listed below are partial on the same condition.

---

## 2. Entity-relationship overview

```
Settings 1──1 (owner)            DeviceSettings (per device, not synced)
Currency 1──* ExchangeRate
Currency 1──* Account ──* TransactionLeg *──1 Txn
                                             │
 Category (self-parent, 2 levels) 1──* Txn ──┤──* TransactionTag *──1 Tag
 Payee 1──* Txn                              │──* Attachment
                                             │──0..1 Split ──* SplitPayer ─┐
                                             │            └──* SplitShare ─┤──1 Person
                                             │──0..1 Loan / LoanPayment     │
                                             │──0..1 Occurrence             │
                                             └──0..1 ImportRow              │
Person (one is_self row) 1──* GroupMember *──1 Group (split_group) ─────────┘
Person 1──* Loan 1──* LoanPayment ──1 Txn
Group 1──* Split        Group 1──* GroupBudget *──1 Budget 1──* CategoryLimit *──1 Category
RecurringItem 1──* Occurrence ──0..1 Txn
RecurringItem 1──* PriceHistory
InstallmentPlan 1──1 RecurringItem      (schedule)   InstallmentPlan 0..1── Loan
Kameti 1──1 RecurringItem (contributions)            Kameti 1──* KametiPayout ──0..1 Txn
FinancialEvent *──0..1 Person / Group / Loan
NotificationRecord ──> (Occurrence | Loan | FinancialEvent | KametiPayout | Budget)   [not synced]
CalendarLink        ──> same sources                                                 [not synced]
ImportBatch 1──* ImportRow ──0..1 Txn        Account 1──* ImportBatch
BackupRecord (metadata only)                                                         [not synced]
```

Design choices:
- **One transaction header + legs.** Every account movement is a `TransactionLeg`. Expense/income = 1 leg, transfer = 2 legs (out and in, each in its own account currency), expense paid by someone else = 0 legs (SPL-06). Account balance is a single `SUM` over legs; transfers cannot be half-saved; cross-currency amounts are both stored exactly. A "pair of transactions" design was rejected: two headers can drift apart and every report must remember to de-duplicate them.
- **Recurring engine is shared.** Bills, subscriptions, income, the car installment and kameti contributions are all `RecurringItem`s with `Occurrence`s, so the Bills & subscriptions hub (REC-07), Calendar, Mark paid (REC-08), reminders and calendar export work the same for all of them. `InstallmentPlan` and `Kameti` add their plan-specific fields.
- **"Me" is a Person row** (`is_self = 1`). Splits, payers and group members reference people uniformly; Splitwise-style maths then needs no special cases.

---

## 3. Entities

Column tables list entity-specific fields; **S** columns are implied unless stated.

### 3.1 Settings (`settings`) — single row, synced
| Field | Swift | SQL | Req | Default | Validation / notes |
|---|---|---|---|---|---|
| id, created_at, updated_at | | | ✓ | | S subset; no soft delete, no is_sample |
| owner_id | `UUID` | TEXT | ✓ | new UUID at first run | Copied into every row |
| base_currency | `CurrencyCode` | TEXT FK currency | ✓ | 'PKR' | Must be enabled currency (CUR-01) |
| budget_period_kind | `BudgetPeriodKind` (.calendarMonth, .salaryCycle) | TEXT | ✓ | 'calendarMonth' | BUD-01, AUD-40 |
| budget_cycle_start_day | `Int` | INTEGER | ✓ | 21 | 1…31; clamped to month length; used when salaryCycle |
| budget_warning_bps | `Int` | INTEGER | ✓ | 8000 | 1000…10000 (BUD-04) |
| salary_day | `Int` | INTEGER | ✓ | 21 | 1…31 (AS-03); forecast fallback when no salary RecurringItem |
| reminder_lead_days | `Int` | INTEGER | ✓ | 1 | 0…30 (CAL-04, AS-05) |
| reminder_time_minutes | `Int` | INTEGER | ✓ | 600 | 0…1439 (10:00) |
| hide_amounts_in_notifications | `Bool` | INTEGER | ✓ | 0 | SEC-04 |
| large_spend_alert_minor | `Int64?` | INTEGER | – | NULL | DSH-07, base currency |
| onboarding_completed_at | `Date?` | INTEGER | – | NULL | |
| last_backup_at | `Date?` | INTEGER | – | NULL | Backup nudge |

### 3.2 DeviceSettings (`device_settings`) — single row, **not synced**
| Field | Swift | SQL | Req | Default | Notes |
|---|---|---|---|---|---|
| id | `UUID` | TEXT PK | ✓ | | |
| app_lock_enabled | `Bool` | INTEGER | ✓ | 0 | SET-01 |
| lock_timeout_seconds | `Int` | INTEGER | ✓ | 60 | one of 0, 60, 300, 900 |
| calendar_export_mode | `CalendarExportMode` (.off, .addOnly, .sync) | TEXT | ✓ | 'off' | SET-04; see ARCHITECTURE §10 |
| calendar_identifier | `String?` | TEXT | – | NULL | EKCalendar id (device-local) |
| sample_mode_active | `Bool` | INTEGER | ✓ | 0 | Shows "Sample data" banner |
| updated_at | `Date` | INTEGER | ✓ | now | |

### 3.3 Currency (`currency`) — reference data
| Field | Swift | SQL | Req | Default | Notes |
|---|---|---|---|---|---|
| code | `CurrencyCode` | TEXT PK | ✓ | | ISO 4217, 3 uppercase letters |
| minor_units | `Int` | INTEGER | ✓ | 2 | 0…3 |
| symbol | `String` | TEXT | ✓ | | "Rs", "$", "€", "£", "AED", "SAR" |
| is_enabled | `Bool` | INTEGER | ✓ | 0 | PKR, USD enabled in v1 |
| sort_order | `Int` | INTEGER | ✓ | 0 | |

Seeded: PKR, USD (enabled), EUR, GBP, AED, SAR (disabled). Adding a currency is a seed row, not a schema change (CUR-01). Never deleted.

### 3.4 ExchangeRate (`exchange_rate`) — S
| Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|
| currency_code | `CurrencyCode` | TEXT FK currency | ✓ | | ≠ base |
| base_currency_code | `CurrencyCode` | TEXT FK currency | ✓ | 'PKR' | |
| rate | `Decimal` | TEXT | ✓ | | > 0; base units per 1 unit; seed USD = "280" (CUR-03) |
| effective_from | `Date` | INTEGER | ✓ | now | |
| source | `RateSource` (.manual, .live later) | TEXT | ✓ | 'manual' | |

- Current rate = latest `effective_from` per pair. History kept (edits add rows) so a report can show which rate was used.
- Unique: (currency_code, base_currency_code, effective_from). Index: (currency_code, effective_from DESC).
- Delete: not user-deletable; superseded rows stay.

### 3.5 Account (`account`) — S
| Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|
| name | `String` | TEXT | ✓ | | 1…40 chars |
| name_key | `String` | TEXT | ✓ | derived | unique |
| kind | `AccountKind` (.cash, .bank, .savings, .creditCard, .wallet, .multiCurrency, .cryptoFiat, .other) | TEXT | ✓ | | ACC-02 |
| currency_code | `CurrencyCode` | TEXT FK currency | ✓ | | Immutable once the account has legs |
| opening_balance_minor | `Int64` | INTEGER | ✓ | 0 | may be negative (credit card) |
| opening_date | `LocalDate` | TEXT | ✓ | today | |
| include_in_totals | `Bool` | INTEGER | ✓ | 1 | DSH-01 |
| symbol_name | `String` | TEXT | ✓ | per kind | SF Symbol (generic, AUD-42) |
| color_hex | `String` | TEXT | ✓ | | `#RRGGBB` |
| sort_order | `Int` | INTEGER | ✓ | 0 | |
| archived_at | `Date?` | INTEGER | – | NULL | ACC-05 |
| institution_hint | `String?` | TEXT | – | NULL | Bank parser id for import ("hbl") |

- Unique: name_key. Index: (archived_at, sort_order).
- Deletion: allowed (soft) only when no live legs reference it; otherwise **archive** (ACC-05). FK from legs is `ON DELETE RESTRICT`.
- Balance is never stored (ACC-03); see §6.

### 3.6 Transaction (`txn`) — S
| Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|
| kind | `TransactionKind` (see table below) | TEXT | ✓ | | |
| status | `TransactionStatus` (.posted, .pending) | TEXT | ✓ | 'posted' | Pending excluded from balances and budgets |
| occurred_at | `Date` | INTEGER | ✓ | now | Instant, UTC |
| local_date | `LocalDate` | TEXT | ✓ | derived | Day in the user's zone at entry; used for grouping, budgets, reports |
| time_zone_id | `String` | TEXT | ✓ | current | e.g. "Asia/Karachi" |
| amount_minor | `Int64` | INTEGER | ✓ | | > 0. Gross amount in `currency_code` (for transfers: sent amount) |
| currency_code | `CurrencyCode` | TEXT FK | ✓ | | Account currency, or chosen when 0 legs |
| my_share_minor | `Int64` | INTEGER | ✓ | = amount | 0…amount. **Computed cache** written by the repository from the split (SPL-05); never user-entered; verified by an integrity test |
| category_id | `UUID?` | TEXT FK category | kind-dependent | | Required for expense, income, refund, installment, kameti kinds; NULL for transfer, loan kinds, settlement |
| payee_id | `UUID?` | TEXT FK payee | – | NULL | |
| note | `String?` | TEXT | – | NULL | ≤ 500 chars |
| fx_rate | `Decimal?` | TEXT | – | NULL | Transfers between currencies: actual rate (base per foreign) implied by the two legs, stored for history (TXN-03, CUR-04) |
| loan_id | `UUID?` | TEXT FK loan | kind-dependent | | loanOut, loanIn, repayment |
| counterparty_person_id | `UUID?` | TEXT FK person | kind-dependent | | settlement: the other person |
| group_id | `UUID?` | TEXT FK split_group | – | NULL | settlement within a group; split expenses carry it on Split |
| refund_of_txn_id | `UUID?` | TEXT FK txn | – | NULL | refund |
| occurrence_id | `UUID?` | TEXT FK occurrence | – | NULL | Posted from a due item |
| kameti_payout_id | `UUID?` | TEXT FK kameti_payout | – | NULL | kametiPayout |
| import_batch_id | `UUID?` | TEXT FK import_batch | – | NULL | |
| source | `EntrySource` (.manual, .voice, .import, .recurring, .notification, .sample) | TEXT | ✓ | 'manual' | |

Kinds and their effects (the single source of truth is `SpendingRules` in UZeeCore):

| kind | Legs | Income/expense reports & budget | Person balance | Category |
|---|---|---|---|---|
| expense | 0 or 1 (−) | spending = my_share | via Split | expense tree |
| income | 0 or 1 (+) | income = my_share | via Split | income tree |
| transfer | 2 (− from, + to) | excluded | – | none |
| refund | 1 (+) | negative spending in its category | via Split if original was split | expense tree |
| adjustment | 1 (±) | excluded (shown as Adjustment, ACC-04) | – | system "Balance adjustment" |
| loanOut (I lend) | 0 or 1 (−) | excluded | + owes me | none |
| loanIn (I borrow) | 0 or 1 (+) | excluded | − I owe | none |
| repayment | 1 (±) | excluded | reduces the loan | none |
| settlement | 1 (±) | excluded | settles splits with counterparty | none |
| kametiContribution | 1 (−) | spending (Financial › Kameti contribution) | – | expense tree |
| kametiPayout | 1 (+) | income (Kameti payout) | – | income tree |
| installment | 1 (−) | spending (e.g. Transport › Car installment) | – | expense tree |

0-leg loans exist only for opening balances (LOAN-08). Kameti contribution/payout counting as spending/income follows PRD Appendix A and the mockups.

- Indexes: (local_date DESC), (kind, local_date), (category_id, local_date), (payee_id), (loan_id), (counterparty_person_id), (occurrence_id), (import_batch_id), (is_sample).
- Unique: occurrence_id (one transaction per occurrence), kameti_payout_id.
- Validation (Core `TransactionValidator`, before every write): legs match kind; leg currency = account currency; for 1-leg kinds |leg| = amount (for a split, = my paid amount from split_payer); transfer from ≠ to; category kind matches (expense/income tree); split totals equal amount.
- Deletion: soft delete → Recently Deleted (TXN-04). Cascade (soft, same deletion_batch_id): legs, split + payers + shares, transaction_tags, attachments, loan_payment. A linked occurrence returns to `scheduled`. Deleting a loanOut/loanIn that created a loan deletes the loan too (asks first). Hard purge after 30 days cascades via FK `ON DELETE CASCADE`.

### 3.7 TransactionLeg (`transaction_leg`) — S
| Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|
| txn_id | `UUID` | TEXT FK txn ON DELETE CASCADE | ✓ | | |
| account_id | `UUID` | TEXT FK account ON DELETE RESTRICT | ✓ | | not archived at write time |
| amount_minor | `Int64` | INTEGER | ✓ | | ≠ 0; negative = money leaves the account |
| currency_code | `CurrencyCode` | TEXT | ✓ | | = account currency |
| role | `LegRole` (.main, .transferOut, .transferIn) | TEXT | ✓ | 'main' | |

- Unique: (txn_id, role). Index: (account_id, txn_id); balance query joins txn for status/deleted/local_date.
- Example: Wise → HBL: leg(Wise, −50000 USD, transferOut), leg(HBL, +13935000 PKR, transferIn), txn.fx_rate = "278.70".

### 3.8 Category (`category`) — S
| Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|
| kind | `CategoryKind` (.expense, .income, .system) | TEXT | ✓ | | |
| parent_id | `UUID?` | TEXT FK category | – | NULL | Parent must have parent_id NULL (2 levels max, CAT-01); same kind |
| name | `String` | TEXT | ✓ | | 1…40 |
| name_key | `String` | TEXT | ✓ | derived | |
| color_hex | `String` | TEXT | ✓ | inherits parent | Top level fixed palette (mockup-dataset) |
| symbol_name | `String` | TEXT | ✓ | inherits parent | SF Symbol |
| sort_order | `Int` | INTEGER | ✓ | 0 | |
| is_hidden | `Bool` | INTEGER | ✓ | 0 | CAT-02 |
| system_key | `String?` | TEXT | – | NULL | Stable key for defaults ("financial.kameti_contribution", "system.adjustment"); lets code find categories after renames |

- Unique: (kind, parent_id, name_key) — `parent_id` coalesced to '' in the index; system_key unique.
- Index: (parent_id, sort_order).
- Merge (CAT-02): reassign txns, limits, recurring items, payee defaults to target in one DB transaction, then soft-delete the source.
- Deletion: only if unused; otherwise the UI requires a merge target. Deleting a parent soft-deletes its children (same batch). System categories cannot be deleted, only hidden.

### 3.9 Payee (`payee`) — S
| Field | Swift | SQL | Req | Default | Notes |
|---|---|---|---|---|---|
| name | `String` | TEXT | ✓ | | "Imtiaz Super Market" |
| name_key | `String` | TEXT | ✓ | derived | unique |
| last_category_id | `UUID?` | TEXT FK category ON DELETE SET NULL | – | NULL | CAT-03, AI-01 |
| last_account_id | `UUID?` | TEXT FK account ON DELETE SET NULL | – | NULL | |
| use_count | `Int` | INTEGER | ✓ | 0 | Suggestion ranking |

Deletion: soft; txns keep the id (shown as the payee name until purge, then NULL via `ON DELETE SET NULL`).

### 3.10 Tag (`tag`) and TransactionTag (`transaction_tag`)
| Table | Field | Swift | SQL | Req | Notes |
|---|---|---|---|---|---|
| tag (S) | name, name_key | `String` | TEXT | ✓ | name_key unique; CAT-04 |
| tag | color_hex | `String?` | TEXT | – | |
| transaction_tag | txn_id | `UUID` | TEXT FK txn ON DELETE CASCADE | ✓ | PK (txn_id, tag_id) |
| transaction_tag | tag_id | `UUID` | TEXT FK tag ON DELETE CASCADE | ✓ | Index (tag_id) |
| transaction_tag | created_at, deleted_at, deletion_batch_id | | | | Follows the txn's soft delete |

Deleting a tag soft-deletes its links (restorable together).

### 3.11 Attachment (`attachment`) — S
| Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|
| txn_id | `UUID?` | TEXT FK txn ON DELETE CASCADE | one of | | `CHECK` exactly one of txn_id, loan_id, recurring_item_id is non-NULL (ATT-01) |
| loan_id | `UUID?` | TEXT FK loan ON DELETE CASCADE | one of | | |
| recurring_item_id | `UUID?` | TEXT FK recurring_item ON DELETE CASCADE | one of | | |
| file_name | `String` | TEXT | ✓ | `<id>.<ext>` | Relative to Attachments folder; never the original name |
| content_type | `String` | TEXT | ✓ | | image/jpeg, image/heic, application/pdf |
| byte_size | `Int64` | INTEGER | ✓ | | ≤ 25 MB |
| sha256 | `String` | TEXT | ✓ | | Backup verification |
| display_name | `String?` | TEXT | – | NULL | User-visible label |
| extracted_text | `String?` | TEXT | – | NULL | Vision result (AI-02), never logged |

Index: (txn_id), (loan_id), (recurring_item_id). File removed from disk only at hard purge (ATT-02, DATA-01).

### 3.12 Budget (`budget`), CategoryLimit (`category_limit`), GroupBudget (`group_budget`) — S
| Table | Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|---|
| budget | period_kind | `BudgetPeriodKind` | TEXT | ✓ | from Settings | |
| budget | period_start | `LocalDate` | TEXT | ✓ | | 1st of month, or cycle start day (clamped) |
| budget | period_end | `LocalDate` | TEXT | ✓ | | inclusive; > start |
| budget | total_limit_minor | `Int64` | INTEGER | ✓ | | ≥ 0, base currency |
| budget | currency_code | `CurrencyCode` | TEXT | ✓ | base | |
| budget | copied_from_budget_id | `UUID?` | TEXT FK budget | – | NULL | BUD-05 |
| category_limit | budget_id | `UUID` | TEXT FK budget ON DELETE CASCADE | ✓ | | |
| category_limit | category_id | `UUID` | TEXT FK category | ✓ | | expense category or subcategory (BUD-02) |
| category_limit | limit_minor | `Int64` | INTEGER | ✓ | | > 0 |
| group_budget | budget_id | `UUID` | TEXT FK budget ON DELETE CASCADE | ✓ | | |
| group_budget | group_id | `UUID` | TEXT FK split_group | ✓ | | BUD-07 |
| group_budget | limit_minor | `Int64` | INTEGER | ✓ | | whole-group spend limit |

- Unique: budget (period_start, period_kind); category_limit (budget_id, category_id); group_budget (budget_id, group_id).
- Periods never overlap: switching period kind takes effect from the next period start (the current one is kept).
- BUD-05: when a period is first opened and has no budget, the previous budget and its limits are copied (no rollover). "Unassigned" = total − Σ top-level limits (shown, may be negative → warning).
- Deletion: soft; limits cascade with the same batch. Spent figures are never stored.

### 3.13 Person (`person`) — S
| Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|
| display_name | `String` | TEXT | ✓ | | 1…60 |
| name_key | `String` | TEXT | ✓ | derived | Voice matching (VOX-06) |
| is_self | `Bool` | INTEGER | ✓ | 0 | Exactly one live row = 1 ("You"), created at first run |
| phone | `String?` | TEXT | – | NULL | LOAN-01 |
| notes | `String?` | TEXT | – | NULL | |
| aliases | `[String]` | TEXT (JSON array) | ✓ | `[]` | "Ammi", "Mother" for voice |
| archived_at | `Date?` | INTEGER | – | NULL | |

- Unique: partial `(is_self) WHERE is_self = 1 AND deleted_at IS NULL`. Names are **not** unique (two "Ali"s allowed); index (name_key).
- Deletion: soft only when the person's balance is zero in every currency and no open loans; otherwise archive. The self row cannot be deleted.

### 3.14 Group (`split_group`) and GroupMember (`group_member`) — S
| Table | Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|---|
| split_group | name | `String` | TEXT | ✓ | | "Office", "Trip to Hunza" (SPL-02) |
| split_group | symbol_name, color_hex | `String` | TEXT | ✓ | | |
| split_group | default_split_method | `SplitMethod` | TEXT | ✓ | 'equal' | |
| split_group | currency_code | `CurrencyCode?` | TEXT | – | NULL | Display/settle currency for the group |
| split_group | simplify_debts | `Bool` | INTEGER | ✓ | 1 | Used only when ≥ 3 members (SPL-09, AUD-23) |
| split_group | settle_reminder_rule | `RecurrenceRule?` | TEXT (JSON) | – | NULL | e.g. month-end for Office (SPL-11); materialised as FinancialEvent |
| split_group | archived_at | `Date?` | INTEGER | – | NULL | |
| group_member | group_id | `UUID` | TEXT FK split_group ON DELETE CASCADE | ✓ | | |
| group_member | person_id | `UUID` | TEXT FK person ON DELETE RESTRICT | ✓ | | the self person is always a member |
| group_member | default_weight | `Int?` | INTEGER | – | NULL | For share/percent defaults |
| group_member | sort_order | `Int` | INTEGER | ✓ | 0 | Deterministic rounding order |
| group_member | left_at | `Date?` | INTEGER | – | NULL | Removed members keep history |

- Unique: group_member (group_id, person_id). Index: (person_id).
- Deletion: a group can be soft-deleted only when every member's group balance is zero; otherwise archive. Splits keep `group_id`.

### 3.15 Split (`split`), SplitPayer (`split_payer`), SplitShare (`split_share`) — S
| Table | Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|---|
| split | txn_id | `UUID` | TEXT FK txn ON DELETE CASCADE | ✓ | | unique (one split per txn) |
| split | group_id | `UUID?` | TEXT FK split_group | – | NULL | NULL = split with one person |
| split | method | `SplitMethod` (.equal, .exact, .percent, .shares) | TEXT | ✓ | | SPL-04 |
| split | total_minor | `Int64` | INTEGER | ✓ | | = txn.amount_minor |
| split | currency_code | `CurrencyCode` | TEXT | ✓ | | = txn currency |
| split_payer | split_id | `UUID` | TEXT FK split ON DELETE CASCADE | ✓ | | |
| split_payer | person_id | `UUID` | TEXT FK person | ✓ | | me or another member; for income = who **received** it |
| split_payer | amount_minor | `Int64` | INTEGER | ✓ | | > 0; Σ = total |
| split_share | split_id | `UUID` | TEXT FK split ON DELETE CASCADE | ✓ | | |
| split_share | person_id | `UUID` | TEXT FK person | ✓ | | |
| split_share | input_value | `Int64?` | INTEGER | – | NULL | method input: exact minor / bps / weight; NULL for equal |
| split_share | share_minor | `Int64` | INTEGER | ✓ | | ≥ 0; computed by SplitCalculator; Σ = total |

- Unique: split_payer (split_id, person_id); split_share (split_id, person_id). Index: split_share (person_id), split_payer (person_id), split (group_id).
- Leg rule: if the self person is a payer of an expense, the txn has one leg for **my paid amount** from my account; if I did not pay, 0 legs (SPL-06). `txn.my_share_minor` = my split_share.
- Deletion: follows its txn.

### 3.16 Loan (`loan`) and LoanPayment (`loan_payment`) — S
| Table | Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|---|
| loan | direction | `LoanDirection` (.lent, .borrowed) | TEXT | ✓ | | LOAN-02 |
| loan | person_id | `UUID?` | TEXT FK person | one of | | `CHECK` person_id or institution_name |
| loan | institution_name | `String?` | TEXT | one of | | bank/company lender |
| loan | principal_minor | `Int64` | INTEGER | ✓ | | > 0 |
| loan | currency_code | `CurrencyCode` | TEXT | ✓ | | |
| loan | start_date | `LocalDate` | TEXT | ✓ | today | |
| loan | due_date | `LocalDate?` | TEXT | – | NULL | Reminder + calendar (LOAN-07) |
| loan | interest_rate_bps | `Int?` | INTEGER | – | NULL | simple annual rate; display-only accrual in v1 |
| loan | is_opening_balance | `Bool` | INTEGER | ✓ | 0 | LOAN-08: no account movement |
| loan | written_off_at | `Date?` | INTEGER | – | NULL | Status "Written off" |
| loan | reminder_lead_days, reminder_time_minutes | `Int?` | INTEGER | – | NULL | NULL = global default (CAL-04) |
| loan | notes | `String?` | TEXT | – | NULL | |
| loan_payment | loan_id | `UUID` | TEXT FK loan ON DELETE CASCADE | ✓ | | |
| loan_payment | txn_id | `UUID?` | TEXT FK txn ON DELETE CASCADE | – | | repayment txn (LOAN-03); NULL only for pre-tracking payments on opening-balance loans |
| loan_payment | amount_minor | `Int64` | INTEGER | ✓ | | > 0; Σ payments ≤ principal (+ accrued interest if user confirms) |
| loan_payment | paid_on | `LocalDate` | TEXT | ✓ | | |

- Status is **derived**: Open (no payments), Partially paid, Settled (outstanding = 0), Written off (written_off_at set). Never stored.
- The loan-creating txn (loanOut/loanIn) has `loan_id`; LOAN-05 creates both in one DB transaction.
- Index: loan (person_id), (due_date); loan_payment (loan_id), unique (txn_id).
- Deletion: soft. A loan with payments cannot be deleted until its repayments are deleted (they moved real money). A loan without payments is deleted together with its creating txn (same batch).

### 3.17 InstallmentPlan (`installment_plan`) — S
| Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|
| recurring_item_id | `UUID` | TEXT FK recurring_item | ✓ | | unique; the schedule (monthly, due day 10) |
| lender_name | `String` | TEXT | ✓ | | "Meezan" |
| loan_id | `UUID?` | TEXT FK loan | – | NULL | optional link if tracked as a loan too |
| installment_minor | `Int64` | INTEGER | ✓ | | > 0 (Rs 45,000) |
| currency_code | `CurrencyCode` | TEXT | ✓ | | |
| total_installments | `Int` | INTEGER | ✓ | | 1…600 (36) |
| paid_before_tracking | `Int` | INTEGER | ✓ | 0 | 0…total (14): counted as paid, no txns |
| first_due_date | `LocalDate` | TEXT | ✓ | | of installment #1 |

Derived: paid = paid_before_tracking + paid occurrences; remaining = (total − paid) × installment (Rs 990,000); end date = first_due + (total − 1) months (Jul 2028). Installment number of an occurrence = months since first_due + 1. LOAN-06. Deletion: soft, cascades to its RecurringItem (same batch); posted txns stay.

### 3.18 Kameti (`kameti`) and KametiPayout (`kameti_payout`) — S
| Table | Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|---|
| kameti | name | `String` | TEXT | ✓ | | |
| kameti | recurring_item_id | `UUID` | TEXT FK recurring_item | ✓ | | unique; contribution schedule |
| kameti | contribution_minor | `Int64` | INTEGER | ✓ | | > 0 (20,000) |
| kameti | currency_code | `CurrencyCode` | TEXT | ✓ | | |
| kameti | start_month | `LocalDate` | TEXT | ✓ | | 1st of month (2026-06-01) |
| kameti | duration_months | `Int` | INTEGER | ✓ | | 1…120 (12) |
| kameti | member_count | `Int?` | INTEGER | – | NULL | |
| kameti | committee_contact_person_id | `UUID?` | TEXT FK person | – | NULL | |
| kameti_payout | kameti_id | `UUID` | TEXT FK kameti ON DELETE CASCADE | ✓ | | KAM-01: one or more |
| kameti_payout | expected_date | `LocalDate` | TEXT | ✓ | | |
| kameti_payout | amount_minor | `Int64` | INTEGER | ✓ | | > 0 |
| kameti_payout | account_id | `UUID?` | TEXT FK account | – | NULL | where it will land |
| kameti_payout | received_at | `LocalDate?` | TEXT | – | NULL | set when its txn is posted (KAM-03) |

Derived (KAM-04): contributed = paid occurrences × amount (+ actual amounts if edited); remaining contributions; payouts received/expected; mismatch flag when Σ payouts ≠ contribution × duration ("Check figures with the committee"). Unique: kameti_payout (kameti_id, expected_date). Deletion: soft; cascades to payouts and its RecurringItem.

### 3.19 RecurringItem (`recurring_item`) — S
| Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|
| name | `String` | TEXT | ✓ | | |
| item_type | `RecurringType` (.bill, .rent, .utility, .salaryPayout, .insurance, .membership, .subscription, .income, .installment, .kameti, .other) | TEXT | ✓ | | REC-01; installment/kameti only via their plans |
| direction | `FlowDirection` (.outflow, .inflow) | TEXT | ✓ | | income/salary = inflow |
| amount_minor | `Int64` | INTEGER | ✓ | | > 0 |
| is_estimated | `Bool` | INTEGER | ✓ | 0 | "~Rs 3,250" |
| currency_code | `CurrencyCode` | TEXT | ✓ | | |
| account_id | `UUID?` | TEXT FK account | – | NULL | default account for Mark paid |
| category_id | `UUID?` | TEXT FK category | – | NULL | |
| payee_id | `UUID?` | TEXT FK payee | – | NULL | |
| group_id | `UUID?` | TEXT FK split_group | – | NULL | default split (office rent) |
| split_template | `SplitTemplate?` | TEXT (JSON) | – | NULL | method, payers, shares; Codable, versioned; applied when posting. JSON because it is a template, never aggregated |
| rule_unit | `RecurrenceUnit` (.day, .week, .month, .year) | TEXT | ✓ | 'month' | |
| rule_interval | `Int` | INTEGER | ✓ | 1 | 1…365; quarterly = month×3; custom N |
| anchor_date | `LocalDate` | TEXT | ✓ | | first due date; day-of-month 29–31 clamps to month end |
| end_date | `LocalDate?` | TEXT | – | NULL | |
| occurrence_limit | `Int?` | INTEGER | – | NULL | installments/kameti |
| next_due_date | `LocalDate?` | TEXT | – | derived | **cache** of earliest unresolved occurrence, for hub sorting |
| subscription_status | `SubscriptionStatus?` (.active, .paused, .cancelled) | TEXT | – | NULL | REC-03; NULL for non-subscriptions |
| service_name | `String?` | TEXT | – | NULL | |
| started_on | `LocalDate?` | TEXT | – | NULL | "Since Jan 2025" |
| status_changed_at | `Date?` | INTEGER | – | NULL | cancelled/paused date |
| reminder_lead_days, reminder_time_minutes | `Int?` | INTEGER | – | NULL | override (CAL-04) |
| sort_order | `Int` | INTEGER | ✓ | 0 | |

Index: (next_due_date), (item_type), (subscription_status). Paused/cancelled items generate no new occurrences. Monthly cost (REC-04): normalised in Core (weekly × 52 ÷ 12, yearly ÷ 12, half-up). Deletion: soft; cascades to future unresolved occurrences and price history (same batch); paid occurrences and their txns stay, item_id kept for history.

### 3.20 Occurrence (`occurrence`) — S
| Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|
| recurring_item_id | `UUID` | TEXT FK recurring_item ON DELETE CASCADE | ✓ | | |
| sequence | `Int` | INTEGER | ✓ | | 1-based (installment 15 of 36) |
| scheduled_date | `LocalDate` | TEXT | ✓ | | from rule; identity of the occurrence |
| due_date | `LocalDate` | TEXT | ✓ | = scheduled | user may move one occurrence |
| expected_amount_minor | `Int64` | INTEGER | ✓ | item amount | price in effect on that date |
| status | `OccurrenceStatus` (.scheduled, .paid, .skipped, .snoozed) | TEXT | ✓ | 'scheduled' | REC-02/08 |
| snoozed_until | `LocalDate?` | TEXT | – | NULL | required when snoozed |
| txn_id | `UUID?` | TEXT FK txn ON DELETE SET NULL | – | NULL | required when paid |
| resolved_at | `Date?` | INTEGER | – | NULL | |

- Display state is derived: Paid / Skipped / Overdue (unresolved and due < today) / Due (today) / Upcoming (CAL-02).
- Unique: (recurring_item_id, scheduled_date). Index: (due_date, status), (txn_id).
- Materialisation: RecurrenceEngine keeps occurrences generated through today + 400 days (enough for yearly items and the calendar), extended on launch. Rule edits regenerate only future unresolved occurrences.
- Deletion: follows the item; deleting the paid txn returns it to `scheduled`.

### 3.21 PriceHistory (`price_history`) — S
| Field | Swift | SQL | Req | Notes |
|---|---|---|---|---|
| recurring_item_id | `UUID` | TEXT FK recurring_item ON DELETE CASCADE | ✓ | |
| effective_from | `LocalDate` | TEXT | ✓ | Netflix: 950 until Mar 2026, 1,100 from 2026-04 |
| amount_minor | `Int64` | INTEGER | ✓ | > 0 |
| currency_code | `CurrencyCode` | TEXT | ✓ | |

Unique: (recurring_item_id, effective_from). Written automatically when the item amount changes (REC-03).

### 3.22 FinancialEvent (`financial_event`) — S (Reminder / custom event)
| Field | Swift | SQL | Req | Default | Validation |
|---|---|---|---|---|---|
| kind | `EventKind` (.custom, .loanDue, .followUp, .settleUp) | TEXT | ✓ | 'custom' | CAL-01/03 |
| title | `String` | TEXT | ✓ | | |
| date | `LocalDate` | TEXT | ✓ | | |
| time_minutes | `Int?` | INTEGER | – | NULL | NULL = all-day |
| amount_minor | `Int64?` | INTEGER | – | NULL | optional, with currency |
| currency_code | `CurrencyCode?` | TEXT | – | NULL | required if amount set |
| person_id / group_id / loan_id | `UUID?` | TEXT FKs | – | NULL | follow-ups, settle-up (SPL-11, LOAN-07) |
| repeat_rule | `RecurrenceRule?` | TEXT (JSON) | – | NULL | CAL-03 |
| reminder_lead_days, reminder_time_minutes | `Int?` | INTEGER | – | NULL | override |
| done_at | `Date?` | INTEGER | – | NULL | |
| notes | `String?` | TEXT | – | NULL | |

Index: (date), (person_id), (group_id). Deletion: soft. Loan due dates are read from Loan directly; `.loanDue` events exist only for extra user reminders.

### 3.23 NotificationRecord (`notification_record`) — not synced
| Field | Swift | SQL | Req | Notes |
|---|---|---|---|---|
| id | `String` | TEXT PK | ✓ | = UN request identifier, e.g. `occ:<uuid>:2026-10-09T10:00` |
| source_kind | `NotificationSource` (.occurrence, .loan, .event, .kametiPayout, .budget) | TEXT | ✓ | |
| source_id | `UUID` | TEXT | ✓ | not an FK (source may be purged) |
| fire_at | `Date` | INTEGER | ✓ | |
| state | `NotificationState` (.scheduled, .delivered, .cancelled, .actedOn) | TEXT | ✓ | |
| action | `String?` | TEXT | – | markPaid / snooze / open |
| budget_period_key | `String?` | TEXT | – | dedupe for threshold alerts (budget id + category + level) |
| created_at, updated_at | `Date` | INTEGER | ✓ | |

Unique: budget_period_key (when not NULL). Index: (state, fire_at). Pruned after 60 days.

### 3.24 CalendarLink (`calendar_link`) — not synced
| Field | Swift | SQL | Req | Notes |
|---|---|---|---|---|
| item_key | `String` | TEXT PK | ✓ | `occ:<uuid>`, `loan:<uuid>`, `evt:<uuid>:<date>` |
| event_identifier | `String` | TEXT | ✓ | EKEvent id |
| calendar_identifier | `String` | TEXT | ✓ | |
| content_hash | `String` | TEXT | ✓ | skip unchanged events |
| updated_at | `Date` | INTEGER | ✓ | |

CAL-06. Cleared when export is turned off (after removing the events in sync mode).

### 3.25 ImportBatch (`import_batch`) and ImportRow (`import_row`) — S
| Table | Field | Swift | SQL | Req | Default | Notes |
|---|---|---|---|---|---|---|
| import_batch | account_id | `UUID` | TEXT FK account | ✓ | | IMP-01 |
| import_batch | parser_id, parser_version | `String`, `Int` | TEXT, INTEGER | ✓ | | "hbl", 1 (IMP-06) |
| import_batch | file_sha256 | `String` | TEXT | ✓ | | re-import warning |
| import_batch | source_file_name | `String` | TEXT | ✓ | | |
| import_batch | statement_from, statement_to | `LocalDate?` | TEXT | – | | |
| import_batch | closing_balance_minor | `Int64?` | INTEGER | – | | reconciliation |
| import_batch | status | `ImportStatus` (.review, .committed, .cancelled) | TEXT | ✓ | 'review' | |
| import_batch | committed_at | `Date?` | INTEGER | – | | |
| import_row | batch_id | `UUID` | TEXT FK import_batch ON DELETE CASCADE | ✓ | | |
| import_row | row_index | `Int` | INTEGER | ✓ | | unique (batch_id, row_index) |
| import_row | local_date | `LocalDate` | TEXT | ✓ | | |
| import_row | amount_minor | `Int64` | INTEGER | ✓ | | signed: − debit, + credit |
| import_row | description | `String` | TEXT | ✓ | | editable (IMP-02) |
| import_row | raw_text | `String` | TEXT | ✓ | | dropped (set '') 30 days after commit |
| import_row | fingerprint | `String` | TEXT | ✓ | | sha256(account, date, amount, normalised description) |
| import_row | suggested_category_id, payee_id | `UUID?` | TEXT FKs | – | | |
| import_row | decision | `ImportDecision` (.include, .exclude) | TEXT | ✓ | 'include' | duplicates default exclude |
| import_row | duplicate_of_txn_id | `UUID?` | TEXT FK txn ON DELETE SET NULL | – | | IMP-03 |
| import_row | created_txn_id | `UUID?` | TEXT FK txn ON DELETE SET NULL | – | | after commit |

Index: import_batch (account_id, status), (file_sha256); import_row (fingerprint). Deletion: cancelling a review hard-deletes the batch (no txns exist). A committed batch can be "undone" as one Recently Deleted batch (its txns share a deletion_batch_id).

### 3.26 BackupRecord (`backup_record`) — not synced
| Field | Swift | SQL | Req | Notes |
|---|---|---|---|---|
| id | `UUID` | TEXT PK | ✓ | |
| kind | `BackupKind` (.manual, .preMigration, .preRestore) | TEXT | ✓ | |
| created_at | `Date` | INTEGER | ✓ | |
| file_name | `String` | TEXT | ✓ | export name or local safety-copy path |
| byte_size | `Int64` | INTEGER | ✓ | |
| schema_version | `String` | TEXT | ✓ | last migration id |
| app_version | `String` | TEXT | ✓ | "0.3.1 (57)" |
| record_counts | `[String: Int]` | TEXT (JSON) | ✓ | shown in restore summary |

No password, key or salt is ever stored (SEC-03).

### 3.27 Sample-data flag
`is_sample` (S column) on every user-content table. Rules: (1) sample mode seeds the mockup-dataset fixture with `is_sample = 1` and `source = sample`; (2) a repository check rejects any write linking a real row to a sample row (PRV-04, tested); (3) "Remove sample data" hard-deletes `WHERE is_sample = 1` in FK-safe order in one DB transaction (does not go to Recently Deleted), then clears sample notifications/calendar links; (4) real data is untouched (DATA-04 test compares a real-data checksum before and after).

---

## 4. Money and rounding rules

| Rule | Detail |
|---|---|
| Representation | `struct Money { let minor: Int64; let currency: CurrencyCode }`. Arithmetic only between equal currencies (precondition in Debug, `CoreError.currencyMismatch` otherwise). Overflow-checked operators. |
| Input | Amount text parsed with `Decimal` → minor units; more decimals than the currency allows is a validation error (no silent rounding on input). |
| Rounding | **Half-up (away from zero on .5) to the minor unit**, implemented once in `Rounding.halfUp(_ value: Decimal, scale:)` in UZeeCore. Nothing else rounds. |
| Conversion | `converted(to: base, rate:)` = minor × rate (Decimal, adjusted for minor-unit difference) → half-up. $2.99 × 280 = Rs 837.20 → Rs 837. |
| When to convert | Per transaction/account first, then sum in base (Available = Σ converted account balances; budget spent = Σ converted my-shares). Totals carry the footnote "USD at $1 = Rs 280" (AUD-04). |
| Which rate | Totals, budgets, reports: current table rate (CUR-04). Transfers: their own stored legs/rate, never recomputed. |
| Splits | Equal: total ÷ n, remainder minor units given one each in member order starting with the first payer (deterministic). Percent (bps) and shares: half-up per person, then largest-remainder correction so Σ shares = total exactly. Exact: user values must sum to total or save is blocked (SPL-04). |
| Pairwise debts | For each split, person i owes payer j `share_i × paid_j ÷ total`, largest-remainder rounded so each payer's receivables sum exactly. |
| Normalised costs | Monthly equivalent of weekly/yearly/custom items computed with Decimal, half-up once at the end. |
| Interest | Simple: principal × bps/10000 × days/365, half-up; display only in v1. |

---

## 5. Budget derivation

- Period for a date: calendar month, or salary cycle `[startDay of month M, startDay of M+1)`; start day clamped to the month length.
- **Spent** (BUD-03) = Σ over posted, non-deleted txns with local_date in period and kind ∈ {expense, installment, kametiContribution}: `my_share_minor` converted to base; minus refunds (same conversion). Category spent includes its subcategories.
- Remaining = limit − spent (may be negative = over). Utilisation = spent ÷ limit (bps, half-up). Warning at ≥ threshold, alert at > 100% (BUD-04).
- Group budget (BUD-07) uses the **whole-group** amount of split expenses with that group_id (Office Rs 76,000 of 150,000).
- Check against sample: October spent Rs 78,374; left Rs 156,626; Personal over by Rs 1,200.

## 6. Balance derivation (never typed)

| Balance | Rule |
|---|---|
| Account (ACC-03) | `opening_balance_minor + Σ leg.amount_minor` over legs whose txn is posted, not deleted, and `local_date ≥ opening_date`. Legs dated before the opening date (imported history) appear in reports but not in the balance, so importing past statements never double counts. |
| Available (DSH-01) | Σ over non-archived accounts with include_in_totals of the account balance converted to base. Sample: Rs 300,000 + $660 (Rs 184,800) = Rs 484,800. |
| Adjustment (ACC-04) | Reconcile = post an `adjustment` txn of (real − derived). |
| Loan outstanding | principal − Σ payments; 0 if written off. Lent → owes me (+); borrowed → I owe (−). |
| Split pairwise | Per split, pairwise debts as in §4; only pairs that include me affect my person balances. |
| Settlement | I pay q amount a → q's balance toward me +a; q pays me → −a. |
| **Person balance** (SPL-01/07, LOAN-04) | Per currency: Σ loans with q + Σ pairwise split debts between me and q + Σ settlements with q. Positive = "owes you", negative = "you owe". Shown converted to base at table rate with a breakdown (loans / shared). Usama: 10,000 − 5,000 + 20,000 = owes you Rs 25,000. |
| Group balance | Member net = Σ (paid − share) for expenses + Σ (share − received) for income + settlements within the group, per currency, displayed in group currency at table rate. Office: +30,000 − 6,400 − $125 (Rs 35,000) + 1,600 = you owe Rs 9,800. |
| Overall (DSH-03/06) | "You are owed" = Σ positive person balances; "You owe" = Σ negative (sample: Rs 35,000 / Rs 88,000). |
| Simplify debts (SPL-09) | Within a group of ≥ 3: take member nets, repeatedly match the largest debtor with the largest creditor (ties by member sort_order) → at most n − 1 suggested payments. Greedy, deterministic; suggestions only, nothing is stored until a settlement is recorded. |
| Forecast (DSH-04) | Available − Σ unresolved outflow occurrences (incl. overdue) due before the next salary occurrence, my share only. Sample: Rs 484,800 − 87,050 = Rs 397,750. |

---

## 7. Deletion summary (DATA-01)

| Action | Behaviour |
|---|---|
| Delete (user) | Soft: set `deleted_at` + one `deletion_batch_id` on the row and its owned children (cascade table per entity above). Appears in Recently Deleted with days left. |
| Restore | Clears both columns for the whole batch; re-validates (e.g. account still exists or is unarchived; name clash → rename prompt). |
| Purge | After 30 days (launch + daily BG task): hard `DELETE`; FKs `ON DELETE CASCADE` remove children; attachment files removed. |
| Blocked deletes | Account with legs → archive. Person/group with non-zero balance → archive. Category in use → merge. Loan with payments → delete payments first. System rows (self person, system categories, currencies) never. |
| References to soft-deleted rows | Allowed temporarily (a txn whose payee is in Recently Deleted still shows the payee name). FK `SET NULL` or `CASCADE` applies only at purge. |

---

## 8. Schema migration strategy (DATA-05)

| Item | Rule |
|---|---|
| Baseline | `v1_baseline` creates all tables above, indexes, seed currencies, rate (USD 280), self person, default category tree (Appendix A, with system_keys). |
| Additive only | Later migrations add tables, nullable columns or columns with defaults, and indexes. Renames/drops/type changes use SQLite's table-rebuild pattern inside one migration and need a written reason in the migration file. |
| Immutable | A shipped migration is never edited; fixes go in a new migration. Names: `v<N>_<what>`. |
| Data migrations | Allowed inside a migration if pure SQL or using frozen record types defined in the migration file (never current model types, which will change). |
| Safety | Safety copy before migrating, `foreign_key_check` + `integrity_check` after, rollback to the copy on failure (ARCHITECTURE §6). |
| Enums | No CHECK constraints on enum columns, so new cases need no migration. |
| Tests | Per released version a fixture DB in `UZeeDataTests/Fixtures/schema-vN.sqlite`; tests: (1) migrate every fixture to latest; (2) headline balances unchanged; (3) `DatabaseMigrator` from empty equals migrated-from-fixture schema (compare `sqlite_master`); (4) backup from older version restores into latest. |
| Sync readiness | Future sync columns (`sync_state`, system fields) arrive as an additive migration; no existing column changes. |

---

## 9. Entity → requirement map

| Entity | Requirements |
|---|---|
| Settings / DeviceSettings | SET-01…04, BUD-01, BUD-04, CAL-04, CUR-01, SEC-04, AS-03…06, DATA-04 |
| Currency, ExchangeRate | CUR-01…05 |
| Account | ACC-01…06, DSH-01 |
| Transaction, TransactionLeg | TXN-01…08, ACC-03/04, CUR-02/04, SPL-06, LOAN-05, KAM-03, REC-02 |
| Category, Payee, Tag | CAT-01…04, AI-01 |
| Attachment | ATT-01/02, AI-02 |
| Budget, CategoryLimit, GroupBudget | BUD-01…07, RPT-03, DSH-01 |
| Person | LOAN-01/04, SPL-01/07, VOX-06 |
| Group, GroupMember | SPL-02, SPL-09, SPL-11/12, RPT-06 |
| Split, SplitPayer, SplitShare | SPL-03…07, SPL-10, BUD-07, TXN-02 |
| Settlement (txn kind) | SPL-08 |
| Loan, LoanPayment | LOAN-02…05, LOAN-07/08, RPT-05 |
| InstallmentPlan | LOAN-06, REC-07 |
| Kameti, KametiPayout | KAM-01…04, REC-07 |
| RecurringItem, Occurrence, PriceHistory | REC-01…08, CAL-01/02/05, DSH-02/04, RPT-04 |
| FinancialEvent | CAL-01/03, LOAN-07, SPL-11 |
| NotificationRecord | CAL-04/05, BUD-04, PRD §15 |
| CalendarLink | CAL-06, SET-04 |
| ImportBatch, ImportRow | IMP-01…07 |
| BackupRecord | DATA-02, DATA-05, PRD §13 |
| deleted_at / deletion_batch_id | DATA-01, TXN-04 |
| is_sample | DATA-04, PRV-04 |
| id / owner_id / timestamps | DATA-06, PRD §14, §18 |
