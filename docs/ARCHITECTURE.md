# UZee — Architecture

| | |
|---|---|
| Version | 0.1 (2026-10-06) |
| Status | Draft — awaiting user review |
| Inputs | PRD v0.3, DISCOVERY.md, design-audit.md, mockup-dataset.md, tech-decisions brief (2026-10-06) |
| Companion | [DATA_MODEL.md](DATA_MODEL.md) — every table, field, index and rule |

The tech-decisions brief is binding. This document explains how each decision is applied and why. Requirement IDs refer to the PRD.

Design priorities, in order (Discovery §1): data integrity → correct money math → security → reliability → usability → performance → polish → extra features. Where two options were close, the one that protects data integrity and testability won.

---

## 1. Recommended stack

| Area | Choice | Why |
|---|---|---|
| Language | Swift 6, strict concurrency on | Data-race safety is checked by the compiler; one language for app, logic and tests. |
| UI | SwiftUI only, no third-party UI libraries | Native look, light/dark, Dynamic Type and VoiceOver for free (NFR-04, A11Y-01…04). iOS 26 TabView, glass and NavigationSplitView match the approved mockups. |
| Platforms | Universal iPhone + iPad, iOS/iPadOS 26.0 minimum | NFR-02/03. iOS 26 is required for Foundation Models (VOX-08) and SpeechAnalyzer; one OS floor avoids `if #available` branches. |
| Toolchain | Xcode 27 on the user's M1 Mac; GitHub Actions macOS runners | Native iOS needs Xcode. CI gives a clean, repeatable build and test run on every push. |
| Persistence | SQLite via **GRDB** (only third-party dependency, SPM) | Explicit versioned migrations (DATA-05), real unique constraints and foreign keys, multi-statement transactions (a split expense writes 5+ rows atomically), fast SQL aggregates for reports (PRF-03), in-memory databases for tests. SwiftData was rejected: implicit migrations, no partial unique indexes, weaker control over transactions and SQL, harder to unit test, and its CloudKit mode forbids unique constraints. Core Data: same constraint problems, more boilerplate. |
| Money | `Int64` minor units + ISO code; rates as `Decimal` | NFR-06, CUR-02. No binary floating point anywhere money is touched. |
| Charts | Swift Charts | Native, accessible (audio graphs, chart summaries), dark mode. |
| Voice / AI | App Intents + App Shortcuts, Speech (SpeechAnalyzer), Foundation Models, Vision | All on device (PRV-01, VOX-08). No network, no API keys. |
| Security | LocalAuthentication, iOS Data Protection, CryptoKit | Built-in, audited, no key management server needed. |
| Notifications / calendar | UserNotifications, EventKit | The only system routes for local reminders and iOS Calendar. |
| PDF | PDFKit (read statements, render report PDFs) | Native text extraction and PDF rendering (IMP-01, RPT-09). |
| Tests | Swift Testing (unit), XCTest UI tests (smoke) | Swift Testing has parameterised tests, ideal for money tables. UI testing still requires XCTest. |
| Analytics / crash SDKs | None | NFR-05, SEC-05: no network calls in v1. |

---

## 2. Application architecture

Layered, ports-and-adapters. Pure domain logic in the middle; Apple frameworks and the database at the edges behind protocols defined in UZeeCore.

```
┌──────────────────────────────────────────────────────────────────────────┐
│ UZee app target (composition root)                                       │
│  UZeeApp · AppContainer · AppDelegate (notification responses, BG tasks) │
│  AppShortcutsProvider · Info.plist · entitlements · xcconfig             │
└───────────────┬───────────────────────────────┬──────────────────────────┘
                │ builds & injects               │ registers
┌───────────────▼──────────────┐  ┌──────────────▼───────────────────────────┐
│ UZeeUI                       │  │ UZeeSystem                               │
│  DesignSystem (tokens,       │  │  NotificationScheduler (64 cap)          │
│   MoneyText, CategoryChip…)  │  │  CalendarExporter (EventKit)             │
│  Features/* Views +          │  │  Intents (App Intents, Siri, controls)   │
│   @Observable ViewModels     │  │  VoiceParser (Foundation Models, Speech) │
│                              │  │  AppLock (LocalAuthentication)           │
│                              │  │  ReceiptReader (Vision)                  │
└───────────────┬──────────────┘  └──────────────┬───────────────────────────┘
                │ uses protocols (ports)         │ implements ports, uses repos
┌───────────────▼────────────────────────────────▼───────────────────────────┐
│ UZeeCore  (pure Swift, Foundation only, builds and tests on Linux)          │
│  Money · CurrencyConverter · Rounding                                       │
│  Domain models (Account, Transaction, Split, Loan, RecurringItem, Kameti…)  │
│  Engines: Balances · BudgetEngine · SplitCalculator · DebtSimplifier        │
│           RecurrenceEngine · KametiEngine · InstallmentEngine · Forecast    │
│           VoiceResolver (matching, amount parsing) · ReminderPlanner        │
│  Ports: *Repository protocols, Clock, NotificationScheduling,               │
│         CalendarExporting, VoiceParsing, AppLocking, ReceiptReading         │
│  Errors: CoreError                                                          │
└───────────────▲────────────────────────────────────────────────────────────┘
                │ implements repository ports
┌───────────────┴────────────────────────────────────────────────────────────┐
│ UZeeData  (GRDB)                                                           │
│  AppDatabase (DatabasePool, WAL) · Migrations (v1_baseline, v2_…)          │
│  Records (GRDB row types) ↔ Core models · Repositories                     │
│  SampleData (fixture = docs/mockup-dataset.md) · Purge (Recently Deleted)  │
│  Backup/Restore (CryptoKit) · Export (CSV, report PDF)                     │
│  Import (PDFKit text extraction, per-bank parsers, dedupe)                 │
└────────────────────────────────────────────────────────────────────────────┘
```

Dependency rule: arrows point inward. UZeeCore depends on nothing but Foundation. UZeeUI depends only on UZeeCore (protocols), so screens are testable and previewable with in-memory fakes. Only the app target knows all four packages.

Data flow for a write (e.g. "Mark paid"):

```
View → ViewModel.markPaid() → OccurrenceRepository.markPaid(draft)   [Core port]
     → UZeeData: one DB transaction: insert txn + legs (+ split) → update occurrence → touch updated_at
     → ValueObservation fires → Home / Calendar / Hub view models refresh
     → ChangeBus event → NotificationScheduler.refresh() and CalendarExporter.sync() (debounced)
     → UI shows "Paid · Undo" toast for 5 s (AUD-13); Undo = soft delete of what was created
```

### Navigation (from the approved design)
- iPhone: `TabView` with Home · Activity · Budget · Calendar · People, plus a separate trailing "+" (add) button. Each tab owns a `NavigationStack` with a typed `Route` enum, so Back always names the previous screen (AUD-12/14).
- iPad: `NavigationSplitView` with a sidebar listing the same five destinations plus Bills & subscriptions, Reports, Accounts and Settings.
- Bills & subscriptions hub (REC-07) is the single home for recurring items, the kameti and the car installment; there are no separate kameti/installment sections, only detail screens pushed from the hub, Home and Calendar.
- Deep links (`uzee://occurrence/<id>`, `uzee://person/<id>`…) are used by notifications, App Intents and widgets (later); they resolve to `Route` values.

### Module boundaries (PRD §18)
Feature folders map 1:1 to modules: Accounts, Transactions, Budget, People & Groups, Loans, Recurring (incl. Kameti, Installments), Calendar & Reminders, Reports, Voice, Import, Settings & Data. A new module (e.g. Savings goals, widgets, SMS capture) adds: Core models + engine, a migration, a repository, a feature folder. No existing table changes shape.

---

## 3. Folder structure

```
Uzee/
├── UZee.xcodeproj
├── App/                                   # app target: composition root only
│   ├── UZeeApp.swift                      # @main, scenes, scenePhase (lock, privacy cover)
│   ├── AppContainer.swift                 # builds DB, repos, services; injected via Environment
│   ├── AppDelegate.swift                  # UNUserNotificationCenterDelegate, BGTaskScheduler
│   ├── UZeeShortcuts.swift                # AppShortcutsProvider (phrases)
│   ├── Resources/  Assets.xcassets · Localizable.xcstrings · PrivacyInfo.xcprivacy
│   └── (Info.plist generated from build settings; entitlements added when needed)
├── Config/  Base.xcconfig · Debug.xcconfig · Release.xcconfig · Version.xcconfig
├── Packages/
│   ├── UZeeCore/
│   │   ├── Package.swift                  # no dependencies; platforms iOS 26 + Linux
│   │   ├── Sources/UZeeCore/
│   │   │   ├── Money/        Money.swift · CurrencyCode.swift · ExchangeRate.swift · Rounding.swift
│   │   │   ├── Models/       Account · Transaction · Split · Person · Group · Loan · Recurring · Kameti …
│   │   │   ├── Ledger/       BalanceCalculator · TransactionValidator · SpendingRules
│   │   │   ├── Budget/       BudgetPeriod · BudgetEngine
│   │   │   ├── Shared/       SplitCalculator · PairwiseLedger · DebtSimplifier
│   │   │   ├── Loans/        LoanCalculator · InstallmentEngine
│   │   │   ├── Recurring/    RecurrenceRule · RecurrenceEngine · KametiEngine · SubscriptionCost
│   │   │   ├── Planning/     Forecast (until next salary) · ReminderPlanner
│   │   │   ├── Voice/        VoiceCommand (draft model) · EntityMatcher · AmountParser · QueryEngine
│   │   │   ├── Ports/        Repositories.swift · Services.swift · Clock.swift
│   │   │   └── Errors/       CoreError.swift
│   │   └── Tests/UZeeCoreTests/            # Swift Testing; runs on macOS and Linux
│   ├── UZeeData/
│   │   ├── Package.swift                  # depends on UZeeCore, GRDB
│   │   ├── Sources/UZeeData/
│   │   │   ├── Database/     AppDatabase · StorageLocation · Migrations/ (v1_baseline.swift, …)
│   │   │   ├── Records/      GRDB record types + mapping to Core models
│   │   │   ├── Repositories/ one per aggregate (Transactions, Accounts, People, Recurring …)
│   │   │   ├── SampleData/   SampleDataset.swift (mockup-dataset.md) · SampleDataService
│   │   │   ├── Maintenance/  RecentlyDeletedPurger · SafetyCopy · IntegrityCheck
│   │   │   ├── Backup/       BackupWriter · BackupReader · BackupFormat (CryptoKit)
│   │   │   ├── Export/       CSVExporter · ReportPDFRenderer
│   │   │   └── Import/       PDFTextExtractor · BankDetector · Parsers/ (HBL, Meezan, Wise, …) · Deduplicator
│   │   └── Tests/UZeeDataTests/            # migrations, repositories, backup round-trip, parsers
│   ├── UZeeSystem/
│   │   ├── Sources/UZeeSystem/
│   │   │   ├── Notifications/ NotificationScheduler · NotificationContentBuilder · ActionHandler
│   │   │   ├── Calendar/      CalendarExporter · CalendarPermission
│   │   │   ├── Intents/       AddExpenseIntent · AskUZeeIntent · LogLoanIntent · entities · controls
│   │   │   ├── Voice/         SpeechTranscriber · FoundationModelParser · @Generable schemas
│   │   │   ├── Security/      AppLockService · PrivacyCover
│   │   │   └── Vision/        ReceiptReader
│   │   └── Tests/UZeeSystemTests/
│   └── UZeeUI/
│       ├── Sources/UZeeUI/
│       │   ├── DesignSystem/ Tokens (semantic colours, category palette) · MoneyText · Cards · Toast
│       │   ├── Navigation/   Route · TabRoot · SplitRoot
│       │   ├── Features/     Home · Activity · AddTransaction · Budget · Calendar · People · Groups
│       │   │                 BillsHub · Kameti · Installment · Accounts · Reports · Voice · Import
│       │   │                 Settings · RecentlyDeleted · Onboarding
│       │   ├── ErrorPresentation/ UserMessage.swift   # the single error → text mapping
│       │   └── Preview/      in-memory fakes of Core ports for #Preview
│       └── Tests/UZeeUITests/              # view-model tests with fakes
├── UZeeSmokeTests/                        # XCTest UI smoke tests (SMK-*)
├── scripts/  bump-build.sh · check-secrets.sh · ci-pick-simulators.sh · ci-test-package.sh
├── .github/workflows/  ci.yml
└── docs/
```

Why four packages and not one: compile-time enforcement of the dependency rule (UI cannot import GRDB; Core cannot import UIKit), faster incremental builds, and UZeeCore tests run on Linux in seconds.

---

## 4. State management

| Concern | Approach |
|---|---|
| Screen state | One `@MainActor @Observable final class …ViewModel` per screen. Views hold it with `@State`. No `ObservableObject`/Combine. |
| Data access | View models call repository **protocols** (UZeeCore/Ports). Repositories are `Sendable`, `async`, and run DB work off the main actor. |
| Live updates | Repositories expose `AsyncStream`s backed by GRDB `ValueObservation` (e.g. `observeHomeSummary()`). Any write anywhere refreshes every visible screen; no manual "reload". |
| Dependencies | `AppContainer` (a `Sendable` struct of protocol-typed services) built once at launch and passed through `@Environment(\.container)`. It is the only global. Tests and previews build a container from fakes or an in-memory DB. |
| Derived numbers | Balances, budget left, owed/owing, forecast are computed by UZeeCore engines from repository data, never held as editable state (ACC-03, SPL-07). |
| Drafts | Add / Mark-paid / Settle-up / Voice confirm cards edit a value-type draft (`TransactionDraft`) validated by Core before save. |
| Undo (AUD-13) | Every money action returns the ids it created; the toast's Undo soft-deletes them with one `deletion_batch_id` (they appear in Recently Deleted). |
| Per-device UI prefs | `@AppStorage` for trivial view prefs only (last tab, last account). Never for financial data. |
| Clock and time zone | Injected `Clock` (`now`, `calendar`, `timeZone`) so tests fix "today" to 6 Oct 2026. |

---

## 5. Data models summary

Full definitions: **[DATA_MODEL.md](DATA_MODEL.md)**. Summary:

| Group | Entities |
|---|---|
| Configuration | Settings, DeviceSettings, Currency, ExchangeRate |
| Ledger | Account, Transaction (12 kinds), TransactionLeg, Category, Payee, Tag, TransactionTag, Attachment |
| Budget | Budget, CategoryLimit, GroupBudget |
| People & sharing | Person (incl. the single "me" row), Group, GroupMember, Split, SplitPayer, SplitShare |
| Obligations | Loan, LoanPayment, InstallmentPlan, Kameti, KametiPayout, RecurringItem, Occurrence, PriceHistory, FinancialEvent |
| System | NotificationRecord, CalendarLink, ImportBatch, ImportRow, BackupRecord |

Key rules: UUID ids; `created_at`/`updated_at`/`deleted_at` on every synced table; money = `Int64` minor units + currency code; balances always derived; one leg table carries every account movement (transfer = one transaction with two legs).

---

## 6. Database, persistence and migrations

| Topic | Decision |
|---|---|
| Engine | SQLite (system library) via GRDB 7.x `DatabasePool` in WAL mode: concurrent reads while writing; reports never block the UI. |
| Location | `Application Support/UZee/uzee.sqlite` (+ `-wal`, `-shm`), behind `StorageLocation`. Attachments in `Application Support/UZee/Attachments/<uuid>.<ext>`. Not excluded from the iOS device backup, so restoring a phone keeps the data. Moving to an App Group container (for future widgets, AUD-43) is a one-time file move handled by `StorageLocation`. |
| Pragmas | `foreign_keys = ON`, `journal_mode = WAL`, `synchronous = NORMAL` (FULL during migration/restore). |
| Transactions | Every user action is one `db.write { }` block. A failed validation or constraint rolls back everything; no partial transfers or splits. |
| Ids | Text UUIDs generated in Swift. SQLite's internal rowid is never read or referenced. |
| Queries | Reports use SQL aggregates over indexed columns (`local_date`, `account_id`, `category_id`); currency conversion and rounding happen in UZeeCore after aggregation per currency, so the rounding rule stays in one place. |
| Migrations | GRDB `DatabaseMigrator`. `v1_baseline` creates the full v1 schema. Every later change is a new, append-only, named migration (`v2_add_savings_goal`, …). Shipped migrations are never edited. `eraseDatabaseOnSchemaChange` is **never** enabled, not even in Debug, because Debug builds run on the owner's real phone. |
| Before migrating | If `migrator.hasCompletedMigrations` is false: `SafetyCopy` writes `pre-migration-<schemaVersion>-<date>.sqlite` using SQLite's online backup API, then migrates under `synchronous = FULL`, then runs `PRAGMA foreign_key_check` + `integrity_check`. On failure the app restores the copy and shows a blocking "Update could not convert your data" screen with Export options (DATA-05). Keep the last 2 safety copies. |
| Migration tests | `UZeeDataTests/Migrations`: for every released schema version a fixture DB (built from the sample dataset at that version) is committed; tests migrate each to latest and assert row counts and key balances (Rs 484,800 available, Rs 156,626 budget left, Office you owe Rs 9,800) are unchanged. |
| Recently Deleted purge | On launch and daily BG task: hard-delete rows whose `deleted_at` < now − 30 days (children cascade), then remove orphaned attachment files (DATA-01). |

---

## 7. Future cloud sync design (DATA-06, PRD §14)

Not built in v1; the v1 schema is shaped so sync needs no redesign.

| Element | Design |
|---|---|
| Transport | CloudKit private database, one custom zone `UZeeZone`, via `CKSyncEngine` (handles fetch/send scheduling, change tokens, account changes). Needs the paid developer account. |
| Mapping | One CKRecord type per synced table; `recordName` = row UUID; references as UUID strings (no CKReference cascade, so a missing parent never deletes children). |
| Why UUIDs | Two devices create rows offline; UUIDs never collide and are stable across devices. Autoincrement ids would clash and would have to be remapped in every foreign key. |
| Why soft delete | A deletion must propagate as data (`deleted_at` set) so other devices learn about it, and so Recently Deleted restore works across devices. Hard purge after 30 days sends the CloudKit delete. |
| Change tracking | Additive migration later adds `sync_state` (dirty flag, last server change tag, system fields blob) per table or a `sync_outbox` table filled by triggers. `updated_at` is set by repositories on every write. |
| Conflict policy | Field-group last-writer-wins by `updated_at` per record, with these overrides: (1) delete vs edit → the edit wins if it is newer than the delete, else delete; (2) occurrence status `paid` beats `scheduled/snoozed` (never un-pay); (3) a transaction and its legs/split are one aggregate, the newer version replaces the whole aggregate, so totals stay consistent; (4) Settings: per-field LWW. |
| Invariants after merge | After each sync batch, run the same validators as local writes (split totals, transfer has 2 legs). A violating aggregate is kept, flagged "Needs review", and listed in Settings › Data. |
| Not synced | DeviceSettings (lock, calendar id, notification state), NotificationRecord, CalendarLink, BackupRecord, ImportBatch raw text. These are per device. |
| Multi-user later (SPL-13) | Every synced row carries `owner_id`; sharing would use CloudKit shared zones per Group. |

---

## 8. Authentication (SET-01, SET-02, SEC-02)

No accounts or sign-in (PRV-02). Optional local app lock, off by default.

| Item | Design |
|---|---|
| Unlock | `LAContext.evaluatePolicy(.deviceOwnerAuthentication)` — Face ID / Touch ID with device-passcode fallback. No app-specific passcode to forget. `NSFaceIDUsageDescription` set. |
| When locked | On launch, and on return to foreground after the lock timeout. Timeout options: Immediately, 1 min, 5 min, 15 min (default 1 min). Time away measured from the moment of backgrounding using wall clock + `ProcessInfo.systemUptime` so changing the clock does not bypass it. |
| Lock screen | Full-screen cover with app icon and "Unlock" button; nothing rendered behind it until unlocked. |
| App switcher privacy | When lock is on: on `scenePhase == .inactive` a privacy cover (blur + logo) is placed over the window **before** iOS takes the snapshot, so amounts never appear in the switcher (SET-02). |
| Notifications | With lock on, "Mark paid" action is `.authenticationRequired`. Amount hiding in notification text is a separate setting (SEC-04). |
| Intents | Voice queries that reveal amounts require the device to be unlocked (`authenticationPolicy = .requiresAuthentication`) and, if app lock is on, open the app. |
| Device without passcode | Lock toggle disabled with explanation (LA cannot evaluate). |

---

## 9. Encryption

| Layer | Design |
|---|---|
| At rest (SEC-01) | iOS Data Protection on the `UZee` folder and every file: `NSFileProtectionCompleteUntilFirstUserAuthentication`. Encrypted by the OS with a key tied to the passcode; unreadable after reboot until first unlock. **Why not `complete`**: notification actions (Mark paid), background refresh of the 64-notification window and purges must open the DB while the phone is locked. The WAL/SHM files inherit the folder's class. |
| Attachments | Same class; file names are UUIDs, never the original name or merchant. |
| Temp files | Backup staging, import PDFs and report PDFs written to a `tmp/UZee` folder with `complete` protection, deleted after use. |
| Backup files (SEC-03) | Encrypted with the user's password; password never stored (format below). |
| SQLCipher | Not used: it would add a second dependency; Data Protection already encrypts the file, and backups (the copy that leaves the device) are encrypted separately. |

### Encrypted backup format `.uzeebackup` (DATA-02)

```
magic "UZEEBK" | formatVersion u16 = 1 | kdf u8 = PBKDF2-HMAC-SHA256 | iterations u32 = 600_000
| salt[16] | noncePrefix[8] | chunkSize u32 = 1 MiB
| chunks: AES-256-GCM(ciphertext, tag[16]) with nonce = noncePrefix || chunkIndex u32,
          AAD = header bytes || chunkIndex || isFinal flag
```
- Key: PBKDF2-HMAC-SHA256 (CommonCrypto `CCKeyDerivationPBKDF`) over the password and salt → 32-byte master; HKDF-SHA256 (CryptoKit) derives the AES key with info `"uzee-backup-v1-enc"`. A wrong password fails the first chunk's tag check → "Wrong password", nothing changed.
- Chunked GCM keeps memory flat for large attachment sets; the AAD chunk index and final flag detect reordering and truncation.
- Plaintext payload: a simple archive of `manifest.json` (format version, app version, build, schema migration id, created at, record counts, attachment list with SHA-256), `uzee.sqlite` (consistent snapshot via `VACUUM INTO`) and `attachments/*`.
- Restore: decrypt to temp → verify manifest hashes → open snapshot, `integrity_check` → refuse if its schema is newer than the app → show summary (counts, date) → safety copy of current data → migrate snapshot if older → atomic file swap → reschedule notifications, re-sync calendar.

---

## 10. Calendar integration (CAL-06, SET-04, PRD §16)

| Item | Design |
|---|---|
| Default | Off. The in-app month calendar is primary and works without any permission. |
| Permission | Requested only when the user turns on "Add to iOS Calendar" (PRV-03). Default request: **write-only** (`requestWriteOnlyAccessToEvents()`), the least privilege. |
| What is written | One event per upcoming occurrence (bill, subscription, installment, kameti contribution/payout, salary, loan due, follow-up, settle-up, custom event) within a rolling 90-day window; all-day or at reminder time; title like "Netflix · Rs 1,100" (amounts omitted if "Hide amounts" is on). URL field = `uzee://` deep link. Notes say "Created by UZee". |
| Ownership | UZee only touches events it created; each is tracked in `CalendarLink` (item key → `eventIdentifier`, content hash). |
| **Constraint to confirm** | With write-only access iOS lets the app add events but not read them back, choose a calendar, or edit/delete them. CAL-06 ("changes and deletions update it") and SET-04 ("target calendar") need **full access**. Design: the exporter supports both modes. Write-only mode = add-only to the default calendar, with a note "Edits in UZee won't update iOS Calendar". Full-access mode (offered as "Keep iOS Calendar in sync") creates/uses a dedicated "UZee" calendar, updates and deletes via `CalendarLink`. **Recommendation:** offer full access for the sync option because the PRD requires updates; lead to confirm. |
| Sync trigger | After writes affecting dated items (debounced 2 s), on launch, and on `EKEventStoreChanged` (full-access mode, to detect the user deleting the UZee calendar). |
| Denied / revoked | Toggle shows "Calendar access is off" with a Settings link; in-app calendar unaffected. |

---

## 11. Notification system (CAL-04/05, REC-08, LOAN-07, SPL-11, BUD-04, PRD §15)

```
Sources (Occurrences, Loans due, KametiPayouts, FinancialEvents, settle-up rules)
   → ReminderPlanner (UZeeCore, pure): fireDate = dueDate − leadDays at timeOfDay (item override ▸ global default)
   → candidates sorted by fireDate, future only
   → NotificationScheduler (UZeeSystem): keep the nearest 60, reserve 4 slots for immediate alerts
   → diff with UNUserNotificationCenter pending requests by deterministic identifier
   → add missing, remove stale; record in NotificationRecord
```

| Rule | Detail |
|---|---|
| 64-pending cap | iOS keeps at most 64 pending requests. UZee schedules the nearest 60 and refreshes so the window rolls forward. |
| Refresh triggers | App launch and foreground; after any write touching dated items (debounced); `significantTimeChangeNotification` and `NSSystemTimeZoneDidChange` (CAL-07); `BGAppRefreshTask` roughly daily; after restore/import/sample-data toggle. |
| Identifier | `"occ:<occurrenceId>:<fireDateISO>"` (or `loan:`, `evt:`, `kpay:`) so re-planning is idempotent and a moved due date replaces the old request. |
| One per occurrence | CAL-05: no repeat nagging; overdue items are highlighted in app instead. |
| Budget alerts | Evaluated after each spending write; when a period/category first crosses the threshold or 100%, an immediate notification is posted once (deduped through NotificationRecord). |
| Category & actions | `DUE_ITEM` category: **Mark paid** (background, posts the expected amount from the item's default account, then shows "Paid · Undo" next time the app opens; authenticationRequired if lock on), **Snooze 1 day** (background, sets occurrence `snoozed_until`, schedules a new request), **Open** (foreground, deep link to the occurrence sheet). Loans/follow-ups use `FOLLOW_UP` (Open, Snooze). |
| Content | Title = item name; body = amount and "due today / tomorrow"; amounts replaced by "Amount hidden" when the Hide-amounts setting is on (SEC-04). Thread id per item type for grouping. |
| Permission | Requested the first time the user creates a dated item or finishes onboarding step "Reminders", never on first launch. Denied → banner in Calendar with a Settings link; everything else works. |

---

## 12. Backup strategy (DATA-02/05, PRD §13)

| Backup | When | Where | Encrypted |
|---|---|---|---|
| Manual backup | User taps "Back up now" | User picks location via document export (Files, iCloud Drive, AirDrop) | Yes, password |
| Pre-migration safety copy | Before any pending schema migration | App container, last 2 kept | Data Protection |
| Pre-restore safety copy | Before replacing data with a restore | App container, last 2 kept | Data Protection |
| Device backup | iOS iCloud/Finder backup of the app container | Apple | Apple's backup encryption |

- Home/Settings nudge when the last manual backup is older than 30 days or never (mockup: "Last backup: never").
- `BackupRecord` stores metadata only (when, size, counts, kind), never the password.
- Automatic and cloud backup come later with sync (out of scope v1).
- Backup round-trip test (DATA tests): sample data → backup → wipe → restore → identical counts, balances and attachment hashes.

---

## 13. Import pipeline (IMP-01…07, AUD-28)

```
Pick account + PDF (fileImporter) ─► PDFTextExtractor (PDFKit, page text with line positions)
  ─► BankDetector (keyword/layout fingerprints) ─► BankStatementParser for that bank + version
  ─► [ParsedRow] (date, description, debit/credit as minor units, balance if present, raw line)
  ─► Normaliser (date formats, sign, currency = account currency, payee cleanup)
  ─► Deduplicator (vs existing txns and earlier imports)
  ─► Categoriser (payee memory → keyword rules → optional Foundation Models suggestion)
  ─► ImportBatch + ImportRows saved as "In review" (no transactions yet)
  ─► Review screen: edit, exclude, accept duplicates; summary "124 new, 6 duplicates, 3 excluded"
  ─► Commit: one DB transaction creates all transactions (source = import, import_batch_id set)
```

| Topic | Rule |
|---|---|
| Parser contract | `protocol BankStatementParser { static var id: String; static var version: Int; func canParse(_ text: StatementText) -> Bool; func parse(_ text: StatementText) throws(ImportError) -> [ParsedRow] }`. Registered in `ParserRegistry`. |
| Per bank | One parser per bank/wallet format (HBL, Meezan, Wise, Easypaisa, NayaPay, SadaPay…), each built from a real user-supplied sample (IMP-06). |
| Unsupported | No parser matches → "This statement format isn't supported yet" with steps to share a sample. Scanned (image-only) PDFs → same message in v1 (Vision OCR is a later option). |
| Duplicates (IMP-03) | Flag when same account, same local date (±1 day for posting lag), same amount, and not already matched; plus exact fingerprint `sha256(account|date|amount|normalised description)` against earlier import rows. Flagged rows default to excluded; user can include. |
| Re-import | Whole file SHA-256 stored on the batch; importing the same file again warns first. |
| Balance check | If the statement shows a closing balance, the review compares it with UZee's derived balance and offers an Adjustment (ACC-04). |
| Opening date | Rows before the account's opening date are history only: they appear in reports but do not change the current balance (see DATA_MODEL §6). |
| Privacy | Real statements never go into the repo. Parser tests use anonymised extracted-text fixtures (`Tests/Fixtures/statements/hbl-v1.txt`). Imported PDFs are not kept unless the user attaches them. |
| CSV (IMP-07) | Same pipeline with a column-mapping step instead of a bank parser. |

---

## 14. Voice / AI pipeline (VOX-01…08, AI-01…03)

```
Entry: "Hey Siri, ask UZee …" (App Shortcut) · in-app mic · typed text · Action Button / Control
  ─► Transcript (Siri supplies text; in app: SpeechAnalyzer on-device, English)
  ─► Availability check: SystemLanguageModel.default.availability
        unavailable ─► fixed App Intents with parameters + "why" explanation (VOX-08)
  ─► FoundationModelParser: LanguageModelSession + guided generation into @Generable VoiceCommand
        enum VoiceCommand { query(QueryKind, filters) | create(DraftKind, fields) | unclear }
  ─► VoiceResolver (UZeeCore, deterministic, tested on Linux):
        • AmountParser re-reads numbers from the transcript ("20k", "14,517", "$20") and must agree
        • EntityMatcher: people / accounts / categories / payees by normalised + fuzzy name
        • Missing required field ─► follow-up question ("What's your friend's name?") (VOX-05)
        • No person match ─► offer "Create Usama" (VOX-06)
  ─► Query: QueryEngine computes the answer from repositories (numbers never come from the model);
            reply text from templates; overdue items mentioned first (AUD-15)
  ─► Create: TransactionDraft ─► editable Confirmation card ─► user taps Save ─► normal repository write
```

| Rule | Detail |
|---|---|
| Never auto-save | VOX-07. Siri path: the create intent shows the card as a snippet and calls `requestConfirmation`; editing opens the app with the draft. The model output is only ever a draft. |
| Model's job | Classify intent and extract fields. It never computes balances or totals and never writes to the DB. |
| Context | The session gets a short instruction set and the names of people/accounts/categories (not amounts or history) to improve matching. |
| Performance | Prewarm the session when the mic opens; target answer ≤ 3 s (PRF-04). |
| Other AI | AI-01 category suggestion = payee memory first, model second. AI-02 receipt = Vision `RecognizeDocumentsRequest`/text recognition → amount, date, merchant into a draft. AI-03 insights = Core computes deltas; the model only phrases them. |
| Tests (VOX) | Resolver, amount parser and query engine have table tests (e.g. "I sent 20k PKR to a friend…" → lend 20,000 PKR, asks for name). Model-dependent tests run only on capable hardware and are tagged. |

---

## 15. Error handling

| Layer | Error type | Examples |
|---|---|---|
| UZeeCore | `CoreError` | `splitTotalMismatch(expected:actual:)`, `currencyMismatch`, `invalidAmount`, `transferNeedsTwoAccounts`, `categoryDepthExceeded` |
| UZeeData | `DataError` | `constraint(ConstraintKind)`, `notFound`, `migrationFailed`, `backupWrongPassword`, `backupCorrupt`, `backupFromNewerVersion`, `diskFull` |
| Import | `ImportError` | `unsupportedFormat`, `scannedPDF`, `parserFailed(line:)`, `alreadyImported` |
| UZeeSystem | `SystemError` | `permissionDenied(Permission)`, `modelUnavailable(reason)`, `authenticationFailed`, `calendarMissing` |

- Swift 6 typed throws (`throws(DataError)`) at package boundaries so callers handle every case.
- **One place** turns errors into text: `UZeeUI/ErrorPresentation/UserMessage.swift` (title, message, recovery action). No raw `error.localizedDescription` in UI.
- Validation happens before writing (Core validators) and again in the DB (constraints, FKs) as the last line of defence.
- Writes are atomic; on failure nothing changes and the draft stays on screen.
- Fatal states (migration failure, unreadable DB) show a recovery screen offering restore from the safety copy or a backup file, never a crash loop (NFR-07).
- Empty, loading and error states for every screen (AUD-32).

---

## 16. Logging with privacy

- `os.Logger(subsystem: "app.uzee", category: <module>)`; categories: `db`, `migration`, `notifications`, `calendar`, `import`, `voice`, `backup`, `lock`.
- **Never log** amounts, balances, names, payees, notes, account names, transcripts or statement text (SEC-04). Log ids (as `privacy: .private(mask: .hash)`), counts, durations, enum states, error codes.
- All dynamic interpolations are `.private` by default; only static enums and counts marked `.public`.
- `OSSignposter` around launch, report queries and import for performance work (PRF-01…03).
- No third-party crash reporting (NFR-05). MetricKit diagnostics are kept on device and can be shared manually.

---

## 17. Testing architecture

| Level | Tool | Where | Runs on | Priority |
|---|---|---|---|---|
| Money and domain math | Swift Testing, parameterised tables | UZeeCoreTests | macOS + **Linux** | Highest: money, rounding, balances, budgets (incl. salary cycle), splits, simplification, recurrence (month end, leap year, DST/time zone), kameti, installments, forecast, voice resolver |
| Persistence | Swift Testing + in-memory GRDB | UZeeDataTests | macOS | Repositories, constraints, soft delete/restore/purge, migrations from fixtures, backup round-trip, CSV, parsers on text fixtures |
| Sample-data snapshot | Swift Testing | UZeeDataTests | macOS | Seed mockup-dataset.md and assert every headline number: Rs 484,800 · spent Rs 78,374 · left Rs 156,626 · Personal over Rs 1,200 · Office you owe Rs 9,800 · Usama owes Rs 25,000 · subscriptions Rs 14,065/month · until-salary Rs 397,750 |
| System services | Swift Testing with fake `UNUserNotificationCenter`/`EKEventStore` wrappers | UZeeSystemTests | macOS | 64-cap planner, identifiers, time-zone change, calendar diff |
| View models | Swift Testing with fakes | UZeeUI Tests | macOS | Flows, validation messages, undo |
| Smoke UI | XCTest UI tests | UZeeUITests | iPhone + iPad simulators | SMK: launch with sample data, add expense, mark paid, settle up, lock screen appears |

- Test IDs follow the master prompt (SMK, REG, TXN, BUD, LOAN, SPL, SUB/REC, KAM, CAL, ACC, CUR, IMP, DATA, SEC, VOX, BUG) and are written into test names/tags: `@Test("BUD-03 utilisation uses my share", .tags(.bud))`. Each fixed bug adds a `REG-`/`BUG-` test that is never removed.
- Fixed clock (6 Oct 2026, Asia/Karachi) and fixed time zone in all date tests; extra suites run the same cases in UTC and America/New_York.
- UI tests launch with `-UZeeInMemoryStore YES -UZeeSeedSample YES -UZeeDisableAnimations YES`.

### CI (GitHub Actions) — `.github/workflows/ci.yml`

| Job | Runner | Steps |
|---|---|---|
| core-linux | `ubuntu-latest` + Swift 6 toolchain container | `swift test --package-path Packages/UZeeCore` (fast feedback, proves Core has no Apple-only imports) |
| build-test | `macos` runner, Xcode pinned (27.x, or newest available on the image until 27 is there) | resolve packages (cached) → `xcodebuild test` for each package scheme and the app on an iPhone and an iPad simulator → upload `.xcresult` |
| ui-smoke | same runner | UZeeUITests on one iPhone simulator; on PRs to `development`/`main` |

Triggers: push to `feature/*`, PRs to `development` and `main`. A red build blocks merge. Test counts per run are recorded in the build history (honest reporting).

---

## 18. Build configuration

| Config | Use | Settings |
|---|---|---|
| Debug | Development on simulator and the Mac-attached phone | `-Onone`, assertions, `SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG`, bundle id `…uzee.dev`, display name "UZee Dev" so test data never mixes with the real install |
| Release | The build the owner uses daily; later TestFlight | `-O`, whole-module, dead-code stripping, bundle id `…uzee`, no debug menu |

- Settings live in `Config/*.xcconfig`, not the project file, so diffs are readable.
- **Sample data** has two switches: (1) the user-facing "Explore with sample data" mode (DATA-04, in Release too), which seeds flagged records and shows a "Sample data" banner; (2) launch arguments for tests/screenshots: `-UZeeSeedSample YES` (seed on launch) and `-UZeeInMemoryStore YES` (never touch the real file). A `DEBUG`-only Developer menu adds "Reset database" and "Fire test notification".
- Signing: free Apple ID personal team for now (7-day expiry, rebuild weekly from the Mac); paid account later for TestFlight. Capabilities used in v1 avoid ones a free team cannot sign (no iCloud, no push).
- Info.plist usage strings: Face ID, Calendars (write-only and full), Camera, Photos, Speech Recognition, Microphone — each requested only on first use (PRV-03).

---

## 19. Environment configuration

There are no servers, keys or environments in v1 (SEC-05). "Environment" means the app's runtime context:

| Item | Source |
|---|---|
| `AppEnvironment` struct | Built at launch: storage location (file / in-memory), clock, calendar + time zone, locale, feature flags, launch-argument overrides. |
| Feature flags | Static `FeatureFlags` in UZeeCore: `voice` (also gated by model availability), `statementImport` (per registered parser), `cloudSync = false`, `widgets = false`. Changing a flag is a code change with a test, not remote config. |
| Locale | English UI. One `MoneyFormatter` in UZeeUI renders all amounts with western grouping as in the mockups ("Rs 150,000", "$20.00", "≈ Rs 5,600", AUD-04). |
| Future network | Any network feature (live rates CUR-05, sync) must first be added to PRD SEC-05 and to this section. |

---

## 20. Dependency management

- Swift Package Manager only. Exactly one external package: **GRDB.swift**, pinned `.upToNextMinor(from: "7.x.y")`; `Package.resolved` committed. Upgrades are a deliberate PR with the full test suite.
- Local packages referenced by path from the Xcode project.
- No CocoaPods/Carthage, no binary frameworks, no UI libraries, no analytics SDKs.
- Apple frameworks used: SwiftUI, Swift Charts, AppIntents, FoundationModels, Speech, Vision, PDFKit, EventKit, UserNotifications, LocalAuthentication, CryptoKit, CommonCrypto, BackgroundTasks, os.

---

## 21. Versioning

| Item | Rule |
|---|---|
| App version | `MARKETING_VERSION` = `0.MILESTONE.PATCH` (e.g. 0.3.1 = milestone 3, second fix build); 1.0.0 when v1 scope is complete. |
| Build number | `CURRENT_PROJECT_VERSION`, a single monotonically increasing integer in `Config/Version.xcconfig`, bumped by `scripts/bump-build.sh` for every installed build and logged in the build history. |
| Schema version | Name of the last applied GRDB migration (`v1_baseline`, `v2_…`); written into backups. |
| Backup format | `formatVersion` in the file header; readers support all older versions. |
| Parser versions | Each bank parser has its own `version`, stored on ImportBatch. |
| Branches | `main` (stable) · `development` (integration) · `feature/*`; docs branch merges into `development` when the repo is initialised. Tags `v0.M.P` on `main`. |

---

## 22. Expansion points (not built now)

| Later feature | Where it plugs in |
|---|---|
| Savings goals | `Goal` + `GoalContribution` tables (additive migration), GoalEngine in Core, feature folder. Contributions are transfers to a savings account, so no ledger change. |
| Widgets (AUD-43) | Widget extension reading the DB from an App Group container (StorageLocation move) through UZeeData read-only repos; interactive "Paid" via App Intents already in UZeeSystem. |
| Live rates (CUR-05) | New `ExchangeRate.source` value + fetcher in UZeeSystem; conversion code unchanged. |
| SMS capture (AUD-44) | "Log from text" App Intent → same VoiceResolver → "To review" drafts. |
| Repeat reminders (CAL-08), auto-post (REC-06), rollover (BUD-08) | Flags on RecurringItem/Budget and planner rules; additive columns. |
| Sync (DATA-06) | §7. |
