# Changelog

All notable changes to UZee are recorded here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: `0.MILESTONE.PATCH` until 1.0.0 (see MILESTONE_PLAN.md, BUILD_HISTORY.md).

Entries before 0.0.1 are documentation stages and are dated instead of versioned.

## [Unreleased]

Milestone 2 (accounts and money engine) in progress.

## [0.1.0] build 2 — 2026-10-07 — Milestone 1 Navigation shell & design system

### Added
- Five tabs (Home, Activity, Budget, Calendar, People), each keeping its own navigation.
- Floating "+" button that opens the Add sheet from every tab.
- Home toolbar: mic (Ask UZee placeholder) and Settings.
- Settings: sample data on/off, version and database status rows.
- Sample data banner on every tab while sample data is on, with one-step removal.
- Design system components: AmountText, StatusBadge, cards, progress bar and ring, empty / skeleton / alert states, confirm sheet, "Saved · Undo" toast.
- Component gallery (debug builds only).
- PRD §22: Qibla direction and Namaz reminders added as later features.

### Changed
- Launch screen replaced by the tab shell; version and database status moved to Settings.
- CI: the GitHub Mac simulator job runs only on manual runs and on `main`; pushes run Linux checks only. Day-to-day UI tests run on the owner's Mac simulator. iPad boots only after the iPhone step.
- `main` branch created at 4fba7f0 (the 0.0.1 build).

### Fixed
- A sixth "+" tab pushed People into a "More" tab on iPhone; "+" is now a floating button.
- The floating "+" did not open Add with a custom glass layer; it now uses Apple's `.glassProminent` button style.

## [0.0.1] build 1 — 2026-10-06 — Milestone 0 Foundation

### Added
- Universal iPhone + iPad Xcode project (iOS 26+, Swift 6, strict concurrency) with Debug/Release xcconfigs and versioning.
- Local packages: UZeeCore (app info, errors), UZeeData (GRDB database, migration `v1_baseline`, protected storage location), UZeeSystem (logging), UZeeUI (launch screen).
- Launch screen showing version and database status.
- CI: UZeeCore tests on Linux, secret-pattern check, package tests and smoke UI tests on iPhone and iPad simulators.
- First install on the owner's iPhone 17 Pro Max (iOS 27).

## 2026-10-06 — Design approval and planning documents

### Added
- **Design audit** `docs/design-audit.md` (AUD-01…45): one dataset, my-share spending, currency display rules, confirm + Undo for money actions, People tab, Bills & subscriptions hub, accessibility and dark mode findings.
- **Mockup dataset** `docs/mockup-dataset.md`: single source of truth for every sample number (today 6 Oct 2026, $1 = Rs 280); later reused as test oracle.
- **Mockup conventions** `docs/mockup-conventions.md`.
- **Reworked mockups**: 27 boards with the audit applied, all numbers from the dataset (artifact link in PROJECT_STATE).
- **Technical decisions brief** `docs/tech-decisions-brief.md` (binding): Swift 6 + SwiftUI, iOS 26 minimum, GRDB/SQLite, Int64 money, packages UZeeCore/UZeeData/UZeeSystem/UZeeUI, Swift Testing + XCUITest, versioning and branches.
- **Design system and architecture documents**: `DESIGN_SYSTEM.md`, `SCREEN_INVENTORY.md`, `ARCHITECTURE.md`, `DATA_MODEL.md`.
- **Planning documents**: `MILESTONE_PLAN.md` (M0–M12), `TEST_PLAN.md`, `TEST_REGISTRY.md` (313 tests seeded, none run), `BUG_REGISTRY.md`, `BUILD_HISTORY.md`, `DEPLOYMENT_GUIDE.md`, this `CHANGELOG.md`.

### Changed
- **PRD v0.2**: the office-only split (OFF-01…06, withdrawn) replaced by Splitwise-style people and groups (SPL-01…13); Personal/Office sections removed; the office is one group.
- **PRD v0.3**: audit applied — BUD-01 salary-cycle budget option (calendar month stays default), REC-07 one Bills & subscriptions hub that includes kameti and car installment (no separate screens), REC-08 mark Paid/Skip/Snooze everywhere, People is a tab, money actions confirm with Undo.
- **PREREQUISITES**: REQUIRED NOW marked complete and verified (macOS 27.0, Xcode 27.0 beta, Swift 6.4, iOS 26.5 + 27.0 simulators, git user iTech, gh logged in as iumer, 16 GiB free); disk space requirement corrected.
- **PROJECT_STATE**: design approval and audit status recorded.

## 2026-10-05 — Discovery, prerequisites and first PRD

### Added
- **Discovery record** `docs/DISCOVERY.md` (groups 1–8): personal use, PKR base + USD, transfers are not spending, calendar-month budgets, office cost sharing, kameti, configurable reminders, iOS Calendar export, optional Face ID, encrypted manual backup, PDF statement import, receipts, 30-day Recently Deleted, English voice via Siri and in-app mic.
- **Prerequisites** `docs/PREREQUISITES.md` (REQUIRED NOW / LATER / OPTIONAL with verification commands).
- **Build route** decided: cloud-written code, GitHub Actions macOS CI, local install from the owner's Mac with a free Apple ID; TestFlight later with a paid account.
- **PRD v0.1** `docs/PRD.md` with permanent requirement IDs.
- **PROJECT_STATE.md** created.

### Changed
- PREREQUISITES updated with the verified Mac environment and a space check.
