# Changelog

All notable changes to UZee are recorded here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: `0.MILESTONE.PATCH` until 1.0.0 (see MILESTONE_PLAN.md, BUILD_HISTORY.md).

Entries before 0.0.1 are documentation stages and are dated instead of versioned.

## [Unreleased]

Built without per-milestone approval at the owner's request (2026-10-07): M4–M8 back to back, then a whole-app review against the mockups.

## [0.9.4] build 13 — 2026-10-08 — Statement readers for MCB, HBL, Meezan, SadaPay, NayaPay and Wise

Checked on the owner's Mac against their real statements (the files never left the Mac): every file reads in full, and balances or header totals match.

### Added
- Statement import recognises MCB (PDF and CSV), HBL, Meezan Bank, SadaPay, NayaPay (PDF and CSV) and Wise (one PDF per currency), learned from the owner's real statements. Test data is made up in the same layouts; no real statement is in the repository.
- PDFs are rebuilt line by line from where each character sits, so table rows read as one line whatever order the PDF stores its text in.
- Cleaner payees: people's names from transfers, merchants from card payments ("Food Panda Karachi"), "Salary Credit", "Wise fees".
- The review screen says which bank the statement was read as, and warns when the statement's currency differs from the account's.
- An empty statement (e.g. a Wise currency with no activity) says so instead of "can't read this format".
- PDF text is rebuilt from PDFKit's text lines (not single characters, which could pick up the wrong letters), checked against the page's own text, and the PDF is also read in its own text order; the reading with more transactions wins.
- Rows stacked over several lines (date, time, type, details, amount, balance) are read too, e.g. NayaPay PDFs.
- CSV opening and closing balances are read from the header (MCB, NayaPay).

### Fixed
- Ask UZee: saving a confirmation card no longer closes the app. The card's fields read the card after Save had cleared it.
- Add: on iPad the "Enter an amount"-style message is scrolled into view; it sat below the bottom of the shorter sheet.
- Smoke tests on iPad: tabs are tapped through the sidebar or top bar, and search opens from its toolbar button.

## [0.9.3] build 12 — 2026-10-07 — "Wallet pal" icon

### Changed
- New app icon chosen by the owner: a smiling white wallet with a yellow and a blue card, on a fresh green background, with dark and tinted versions (source: docs/brand/make-icon.py).
- The animated logo now matches: the wallet pops in, the cards slide up out of it, the face appears and smiles, then the cards bob and the eyes blink. The launch screen is green to match. Still with Reduce Motion.

### Fixed
- Ask UZee: when a confirmation card appears, the keyboard drops so the whole card, including Save, is on screen.
- Ask UZee: if saving a card fails, the reason shows on the card. Before, it went to an alert that can't appear over the sheet, so Save seemed to do nothing.
- Smoke tests: opening Activity waits for the Settings pop to finish, and the lend-card test reports the card's problem if saving fails.

## [0.9.2] build 11 — 2026-10-07 — Smiley logo

### Changed
- The icon's U is now a smile with two eyes. In the animated logo the eyes pop in after the U draws and blink every few seconds (open and still with Reduce Motion).

## [0.9.1] build 10 — 2026-10-07 — New app icon and animated logo

### Added
- App icon: a glowing cyan-to-pink "U" with AI sparkles on a deep violet and blue background, with dark and tinted versions for the Home Screen (source: docs/brand/uzee-icon.svg, docs/brand/make-icon.py).
- Animated logo: the U draws itself in, its colours flow and the sparkles twinkle. Shown briefly at launch and at the top of Ask UZee; still when Reduce Motion is on.

## [0.9.0] build 9 — 2026-10-07 — Receipt scanning, Ask UZee voice and Siri, statement import (Mac tests pending)

Built on the owner's request to continue until OCR, voice and PDF statement import work (2026-10-07 20:06 UTC).

### Added
- Receipt scanning in Add: take or choose a photo; UZee reads the total, date and shop on the iPhone (Vision), fills them in and attaches the photo when you save (AI-02).
- Ask UZee: type or speak (on-device speech). Answers what you owe or are owed, budget left, spending by category and period, next bill, subscriptions, due before salary, upcoming bills and balances, using the same numbers as the screens (VOX-03). Logs expenses, income, transfers, loans and repayments from one sentence, asks a follow-up when something is missing ("Who did you lend it to?") and always shows an editable card before saving (VOX-04…07). Amounts like "20k", "1.5 lakh", "$20" and "two thousand five hundred".
- Built-in rules understand common sentences on every iPhone; Apple Intelligence (Foundation Models) is used on the device only for sentences the rules don't understand. When it's off, UZee says so (VOX-08).
- Siri: "Hey Siri, ask UZee" answers without opening the app; "Hey Siri, add to UZee" opens Ask UZee with the card; both also appear in Shortcuts and can go on the Action Button. Settings › Siri & voice explains this.
- Statement import (Settings › Import bank statement, or Account › Import statement): PDF (with password prompt) or CSV, read on the iPhone; review screen with suggested categories, editable rows, money in/out from the balance column, and possible duplicates switched off; import in one step with Undo (IMP-01…04, IMP-07).

### Notes
- The statement reader handles the common "date · description · amount · balance" layout. Bank-specific readers (IMP-06/008) need one sample statement per bank.
- Not yet: Control Center control and Lock Screen widget (need a widget extension), reminders/events by voice (VOX-012).

## [0.6.1] build 8 — 2026-10-07 — Sample data fix

### Fixed
- Sample data failed to turn on when you had a real account with the same name as a sample one (for example "Hbl" and sample "HBL"). Account names now only need to be unique among real accounts, and separately among sample accounts. Migration `v8_sample_account_names`.
- Debug builds show the real error when sample data fails.

## [0.6.0] build 7 — 2026-10-07 — Milestones 6–8 Bills, Calendar, Home and Reports (Mac UI tests pending)

### Added
- Bills & subscriptions: monthly and yearly commitments with a mix bar, due now, upcoming with "due before salary", kameti and car installment plan cards, subscriptions, group bills, income, paused / cancelled.
- Item detail: next due with Mark paid, price history, billing details, installment schedule, kameti payouts with the "check figures with the committee" warning, pause / cancel / delete. Add and edit form.
- Mark paid sheet with Skip this time and Snooze 1 day; Undo on every action. Mark paid posts the transaction once and splits group bills equally.
- Calendar: month grid with markers, due-before-salary card, loans due back, day list and agenda.
- Home: overdue strip, budget left, spent vs the same point last month, until next salary, next 7 days, people balances, where it went, insights.
- Reports: income, spending and net; spending by category; six months of income vs spending; budget kept; subscriptions; people and account balances.
- Sample data: 17 recurring items from the mockup dataset.

### Fixed
- GitHub Mac CI compiler crash (a method passed as a Binding setter in Categories).

## [0.5.0] build 6 — 2026-10-07 — Milestone 5 People, loans and splitting

## [0.4.0] build 5 — 2026-10-07 — Milestone 4 Budget

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
