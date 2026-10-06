# Decisions every post-design doc must follow (set by the lead, 2026-10-06)

- App: native Swift 6 + SwiftUI, universal iPhone + iPad, iOS 26.0 minimum, built with Xcode 27 (user's Mac) and GitHub Actions macOS runners. No third-party UI libraries.
- Persistence: SQLite via GRDB (the only third-party dependency, via Swift Package Manager). Reasons: explicit versioned migrations, unique constraints, transactions, fast queries for reports, easy unit tests. All data on device. Files use iOS Data Protection (complete until first unlock). Cloud sync later (CloudKit), so every record has a UUID id, createdAt, updatedAt, deletedAt (soft delete), and no autoincrement ids leak into logic.
- Money: Int64 minor units + ISO currency code (PKR, USD, EUR, GBP, AED, SAR). Never Double. Exchange rates stored as Decimal "base units per 1 unit". Each cross-currency transfer stores its own actual rate. Table rate starts at $1 = Rs 280. Rounding: half-up to minor units, done in one place.
- Code layout: one Xcode app target plus local Swift packages:
  - UZeeCore: pure Swift domain models, Money, calculations (balances, budgets, splits, debts simplification, recurring schedules, kameti, installments). No UI, no Apple-only frameworks, so its tests can also run on Linux.
  - UZeeData: GRDB database, migrations, repositories, sample-data fixture (docs/mockup-dataset.md), backup/restore (CryptoKit AES-GCM, key from password via PBKDF2/HKDF), CSV/PDF export, PDF statement import parsers (PDFKit) per bank.
  - UZeeSystem: notifications (UserNotifications, 64-pending cap scheduler), EventKit calendar export, App Intents + Siri, Apple Foundation Models voice parsing, LocalAuthentication (Face ID), Vision receipt reading.
  - UZeeUI: design-system components and feature screens (SwiftUI, @Observable view models).
- State: @Observable view models per screen, talking to repository protocols; dependency container injected at app start; no global singletons except the container.
- Navigation: TabView with Home, Activity, Budget, Calendar, People + separate "+" add button; each tab owns a NavigationStack. iPad uses NavigationSplitView with a sidebar.
- Tests: Swift Testing for unit tests (core math is the priority), XCTest UI tests for smoke flows, snapshot of sample data. Test IDs as in the master prompt (SMK, REG, TXN, BUD, LOAN, SPL, SUB/REC, KAM, CAL, ACC, CUR, IMP, DATA, SEC, VOX, BUG). Tests never removed from the regression suite.
- Versioning: semantic 0.MILESTONE.PATCH, CFBundleVersion = monotonically increasing build number. Builds installed from the user's Mac with a free Apple ID (7-day expiry); TestFlight later with a paid account.
- Branches: main (stable), development (integration), feature/* branches. Current docs branch claude/project-thread-m75ycs will be merged into development when the repo is initialised.
- Errors and logging: typed errors per layer, user-facing messages from one place, os.Logger with privacy redaction; never log amounts, names or notes.
- Process: master prompt (thread root) rules apply: milestones need acceptance criteria, test cases, DoD; bug regression policy; build history; honest test reporting.
