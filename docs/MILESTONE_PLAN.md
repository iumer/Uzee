# UZee — Milestone Plan

| | |
|---|---|
| Version | 0.1 (2026-10-06) |
| Status | Draft, awaiting user approval |
| Inputs | PRD v0.3, tech-decisions-brief (binding), PREREQUISITES, mockup-dataset, design-audit |
| Related | TEST_PLAN.md, TEST_REGISTRY.md, BUG_REGISTRY.md, BUILD_HISTORY.md, DEPLOYMENT_GUIDE.md |

## 1. Rules for every milestone

1. **One milestone at a time.** A milestone starts only after the previous one is accepted by the owner (master prompt §11, §22). Proceeding with known issues needs the owner's explicit written approval, recorded in PROJECT_STATE.
2. **Version.** Milestone *N* ships as `0.N.0`; fixes inside it are `0.N.1`, `0.N.2`… M0 ships `0.0.1`. `CFBundleVersion` (build number) only ever goes up (1, 2, 3…), across all milestones.
3. **Branches** (§25). Work happens on `feature/mN-<topic>` branches off `development`; merged to `development` when CI is green; `development` → `main` only when a milestone is accepted, tagged `v0.N.0`. A tag is the rollback point before the next milestone.
4. **Tests before build** (§17). No build is handed over unless smoke + milestone + all REG tests + critical integration tests ran and the result is reported in BUILD_HISTORY.md, including failures.
5. **Bugs** (§15). Every reported bug gets a `BUG-nnn`, a root cause and a permanent `REG-nnn` test before it is called fixed.
6. **Sample data.** Expected values in tests come from docs/mockup-dataset.md ("today" = Tue 6 Oct 2026, $1 = Rs 280). The fixture lives in UZeeData and grows each milestone with the entities that milestone adds.
7. **End-of-milestone report** (§22): MILESTONE COMPLETED / IMPLEMENTED / SCREENSHOTS OR UI DESCRIPTION / TEST RESULTS / KNOWN ISSUES / DECISIONS NEEDED, then ask the owner to APPROVE, REQUEST CHANGES or REPORT BUGS. Silence is not approval.

### Definition of Done (applies to every milestone, §34)

| Level | Done when |
|---|---|
| Feature | Implemented + integrated + validated (input rules) + tested (IDs in registry, passing) + documented + no known critical regression |
| Milestone | All required features done + acceptance criteria met + milestone tests pass + smoke pass + all REG pass + CI green on `development` + docs updated (PROJECT_STATE, CHANGELOG, BUILD_HISTORY, TEST_REGISTRY, affected design/architecture docs) + build installed on the owner's iPhone + **owner approval received** |

Each milestone below lists only its extra DoD items.

## 2. Overview

| M | Name | Version | Main PRD ids | Test ids (see TEST_REGISTRY) |
|---|---|---|---|---|
| M0 | Environment & project skeleton | 0.0.1 | NFR-03, NFR-05, NFR-07, SEC-01, DATA-05 (scaffold) | ENV-001…008, SMK-001…004, SMK-011 |
| M1 | Navigation & design-system foundation | 0.1.0 | NFR-02, NFR-04, DATA-04, PRV-04, A11Y-03 | UI-001…012, DATA-001…004, SMK-005, SMK-006 |
| M2 | Accounts & transaction engine | 0.2.0 | ACC-01…06, TXN-01…04, TXN-06, TXN-07, CUR-01…04, NFR-06 | CUR-001…012, ACC-001…008, TXN-001…015, SMK-007…010, SMK-012 |
| M3 | Categories, Activity, search, detail, receipts, Recently Deleted | 0.3.0 | CAT-01…04, TXN-05, TXN-08, ATT-01…02, DATA-01, AI-01 | CAT-001…008, TXN-020…028, ATT-001…004, DATA-010…014 |
| M4 | Budgeting | 0.4.0 | BUD-01…07 | BUD-001…022 |
| M5 | People, loans & Splitwise-style splitting | 0.5.0 | LOAN-01…05, LOAN-08, SPL-01…10, SPL-12 | LOAN-001…012, SPL-001…020 |
| M6 | Bills, subscriptions, kameti & car installment | 0.6.0 | REC-01…05, REC-07, REC-08, KAM-01…04, LOAN-06 | REC-001…015, SUB-001…006, KAM-001…006, LOAN-020…023 |
| M7 | Calendar & reminders | 0.7.0 | CAL-01…07, LOAN-07, SPL-11, KAM-02, SET-03, SET-04 | CAL-001…026 |
| M8 | Home dashboard & reports | 0.8.0 | DSH-01…07, RPT-01…09, DATA-03 | DSH-001…011, RPT-001…013 |
| M9 | Ask UZee voice & Siri | 0.9.0 | VOX-01…08 | VOX-001…015 |
| M10 | Data safety, import, onboarding | 0.10.0 | SET-01, SET-02, DATA-02, DATA-05, IMP-01…07, ACC-06, AI-02, SEC-01…05, PRV-01…03 | SEC-001…008, DATA-020…026, IMP-001…009, UI-030…034 |
| M11 | iPad, dark mode, accessibility & performance | 0.11.0 | NFR-02, NFR-04, A11Y-01…04, PRF-01…04, DSH-07 | UI-040…047, A11Y-001…006, PRF-001…005 |
| M12 | Release preparation | 0.12.0 → 1.0.0 | §28, §29, §30 | REL-001…018 |

Priority S/C items are scheduled where shown; if time runs short they move to the backlog with the owner's agreement, never silently.

---

## M0 — Environment & project skeleton (0.0.1)

**Objective.** A buildable, testable, installable empty app with the agreed structure, so every later milestone only adds features.

**Features.** Xcode project `UZee` (universal, iOS 26.0, Swift 6 strict concurrency); local packages UZeeCore, UZeeData, UZeeSystem, UZeeUI; GRDB via SPM (only third-party dependency); database opened with migration v1 (settings table + `schema_version`) and Data Protection *complete until first unlock*; dependency container; os.Logger with privacy redaction; placeholder launch screen showing "UZee 0.0.1 (1)"; GitHub Actions CI; first smoke tests.

**User stories.**
- As the owner, I can install UZee 0.0.1 on my iPhone from Xcode and it opens without crashing.
- As the owner, I can see on GitHub that every push is built and tested automatically.

**Technical tasks.**
| # | Task |
|---|---|
| 0.1 | Initialise repo branches `main`, `development`; merge docs branch `claude/project-thread-m75ycs` into `development` |
| 0.2 | Create project + 4 local packages; package dependency direction UI → System/Data → Core |
| 0.3 | Add GRDB (pinned exact version); `AppDatabase` with `DatabaseMigrator`, `eraseDatabaseOnSchemaChange = false` |
| 0.4 | Set file protection on DB directory; enable WAL |
| 0.5 | Logger wrapper (`.private` default for interpolations); typed error base types per layer |
| 0.6 | Version settings: `MARKETING_VERSION=0.0.1`, `CURRENT_PROJECT_VERSION=1` in one xcconfig |
| 0.7 | CI workflow `.github/workflows/ci.yml`: job `core-linux` (`swift test` in UZeeCore on ubuntu), job `ios` (macOS runner, latest Xcode, `xcodebuild test` on iPhone + iPad simulators), secret-pattern check, test result bundle uploaded as artifact |
| 0.8 | Smoke UI tests SMK-001…004, SMK-011 (XCUITest) |
| 0.9 | Device spike: confirm free Apple ID signing works and a stub App Intent and Foundation Models availability check compile and run on the iPhone 17 Pro Max (de-risks M9) |

**Dependencies.** PREREQUISITES "REQUIRED LATER A" done (Apple ID in Xcode, iPhone paired, Developer Mode). Owner approval of design system, architecture, data model, this plan and TEST_PLAN.

**Acceptance criteria.**
1. CI is green on `development` for both jobs; failure of any test fails the run.
2. App installs and launches on the owner's iPhone and on iPhone and iPad simulators; no crash on launch or relaunch.
3. Database file exists after first launch, migration v1 recorded, protection class verified.
4. No secrets, certificates or personal data in the repository.
5. BUILD_HISTORY has the 0.0.1 entry with honest test results.

**Test cases.** ENV-001…008, SMK-001, SMK-002, SMK-003, SMK-004, SMK-011.

**Risks.**
| Risk | Mitigation |
|---|---|
| CI runners lack Xcode 27 beta; local beta SDK differs | Code must compile on both; CI uses newest stable Xcode available on the runner; no beta-only APIs without `#available` |
| GitHub macOS minutes limited | `core-linux` job runs most tests cheaply; macOS job on PRs and `development` only |
| Free Apple ID cannot use some capabilities (Siri, iCloud) | Spike 0.9; findings recorded in PROJECT_STATE before M9 |

**Extra DoD.** Owner has installed the build on the iPhone and confirmed the launch screen.

---

## M1 — Navigation & design-system foundation (0.1.0)

**Objective.** The app's shell and reusable components exist, matching the approved mockups, so feature screens are just assembly.

**Features.** TabView: Home, Activity, Budget, Calendar, People + separate round "+" add button (no top segmented controls, AUD-07); each tab with its own NavigationStack; iPad NavigationSplitView with sidebar (basic, polished in M11); Home toolbar mic and gear buttons (placeholders); design tokens (colour, type, spacing, radius 20, fixed category colours); components: MoneyText (native amount + "≈ Rs" secondary line, tabular digits), StatusLabel (word + symbol, never colour only), CategoryIcon, Card, ProgressBar, EmptyState, LoadingState, ErrorBanner, ConfirmSheet, Toast with Undo; sample-data mode switch, "Sample data" banner, one-action removal.

**User stories.**
- As the owner, I can move between the five tabs and open the add sheet from anywhere.
- As the owner, I can turn on sample data to explore the app and remove it without touching my own records.

**Technical tasks.** Design tokens in UZeeUI; component gallery screen (debug builds only); `isSample` flag on every table from the first data migration; `SampleDataService` (load/remove, transactional); sample banner on all tabs; light/dark token sets; Dynamic Type-safe layouts from the start.

**Dependencies.** M0 accepted. Approved DESIGN_SYSTEM and screen inventory.

**Acceptance criteria.**
1. Tab order and "+" button match the Main mockup on iPhone; iPad shows sidebar with the same destinations.
2. Each tab keeps its navigation state when switching tabs.
3. Components render correctly in light and dark mode and at the largest accessibility text size (snapshot reviewed).
4. Sample mode on shows the banner; remove sample data deletes only `isSample = 1` rows (verified by count) in one transaction.

**Test cases.** SMK-005, SMK-006, UI-001…012, DATA-001…004.

**Risks.** Design drift from mockups → screenshot comparison in milestone report. Over-building components → only those used by M2–M4 screens.

**Extra DoD.** Screenshots of every tab (light and dark, iPhone and iPad) attached to the milestone report.

---

## M2 — Accounts & transaction engine (0.2.0)

**Objective.** Correct, exact money: accounts, expenses, income, transfers (with the real rate), multi-currency totals and balances. This is the base of OBJ-5.

**Features.** `Money` (Int64 minor units + ISO code; arithmetic only within one currency; overflow-checked); `ExchangeRate` (Decimal, base units per 1 unit; table $1 = Rs 280, editable); one rounding function (half-up to minor units); accounts (ACC-01…05, ACC-06 suggestions list); transaction types Expense, Income, Transfer, Refund, Adjustment; transfer with sent/received amounts and stored implied rate; balances computed (opening + posted), never stored; Pending excluded from balance; Add sheet (amount first, decimal keypad, account defaults to last used, date/time, payee, note), Transfer sheet (From/To, received amount), confirm + "Saved · Undo" toast; Accounts list and account detail; "repeat this" (TXN-07); `myShare` field on transactions (defaults to full amount; M5 fills splits).

**User stories.** US-02 (quick expense), US-03 ($500 Wise → HBL with the PKR received), "As the owner, I see Rs 484,800 available across 9 accounts with the note USD at $1 = Rs 280".

**Technical tasks.** UZeeCore: `Money`, `Currency`, `RateConverter`, `Rounding`, `BalanceCalculator`, `TransactionValidator`. UZeeData: migration v2 (accounts, transactions, transfer legs, exchange rates; UUID PKs, createdAt/updatedAt/deletedAt), repositories, sample fixture for accounts and October transactions. UZeeUI: Add, Transfer, Accounts screens, view models.

**Dependencies.** M1 accepted.

**Acceptance criteria.**
1. No `Double`/`Float` in any money path (CI grep check on UZeeCore/UZeeData money types).
2. Sample accounts: Rs 300,000 PKR + $660 → total available **Rs 484,800**; HBL Rs 182,400, Wise $520.00 (≈ Rs 145,600).
3. Transfer $500 → Rs 139,350 stores rate 278.70, shows "Rs 650 less than at 280", and does not change income or spending.
4. Expense, income, edit and delete update balances immediately and survive relaunch.
5. Invalid input (zero, empty, over-limit, missing account) is refused with a clear message and nothing is saved.
6. All CUR, ACC, TXN tests of this milestone pass on Linux (core) and simulator (integration/UI).

**Test cases.** CUR-001…012, ACC-001…008, TXN-001…015, SMK-007…010, SMK-012.

**Risks.** Rounding disagreements between screens → single `Rounding` function and display formatter; PKR display rule open: dataset shows whole rupees (Rs 78,374) but DESIGN_SYSTEM shows paisa when non-zero (Rs 78,374.20 from $2.99 × 280); owner/lead decides before M2 starts. Int64 overflow on huge sums → checked arithmetic, error surfaced.

**Extra DoD.** Financial calculation checklist (TEST_PLAN §4) items for addition, subtraction, precision, formatting, negative, large, zero, refunds, transfers all have passing tests.

---

## M3 — Categories, Activity, search & filters, transaction detail, receipts, Recently Deleted (0.3.0)

**Objective.** Every transaction can be categorised, found, inspected, documented with a receipt and safely recovered after deletion.

**Features.** Default two-level category tree (PRD Appendix A, fixed colours), rename/reorder/hide/merge; payees with remembered category (CAT-03); tags; category split of one transaction (TXN-08, C); Activity tab grouped by day with day totals of my share and a line saying what the money did (AUD-03); filters (account, category, tag, type, person/group, date range) via pull-down menus; search (payee, note, amount); transaction detail and edit; receipts and PDFs attached (camera, Photos, Files) stored in protected app storage; Recently Deleted (30 days, restore, purge); on-device category suggestion from payee (AI-01, S).

**User stories.** "As the owner, I find the Imtiaz grocery bill by typing 8940." "As the owner, I restore the Careem ride I deleted by mistake." "As the owner, I attach the tea & snacks receipt to the office expense."

**Technical tasks.** Migration v3 (categories, payees, tags, attachments); FTS5 index for search; attachment store with file protection; purge job on launch (injected clock); category merge in one DB transaction.

**Dependencies.** M2 accepted.

**Acceptance criteria.**
1. Activity for 1–6 Oct shows day totals Tue Rs 16,117, Mon Rs 19,690, Sun Rs 6,200, Sat Rs 2,687, Fri Rs 3,680, Thu Rs 30,000 (my share; transfers and loans shown but not counted).
2. Search and every filter return exactly the expected rows from the sample dataset.
3. Deleted items appear in Recently Deleted (sample: 3 items), restore brings back balances; items older than 30 days are purged.
4. Merging categories moves all transactions; no orphan rows.
5. Attachments survive relaunch and are excluded from logs.

**Test cases.** CAT-001…008, TXN-020…028, ATT-001…004, DATA-010…014.

**Risks.** Search speed with 10k rows → FTS5 + indexes, measured in PRF-002 later. Photo permission denial → Files and camera paths still work.

**Extra DoD.** Day-total expected values match the dataset exactly.

---

## M4 — Budgeting (0.4.0)

**Objective.** The owner always knows how much budget is left, by month or salary cycle, counting only his own share.

**Features.** Monthly budget total (BUD-01) with period setting: calendar month (default) or salary cycle (start day, e.g. 21st → 20th); category and subcategory limits; **unassigned** amount (total − sum of limits); utilization, remaining, over-by; warning threshold (default 80%, editable) and exceeded alert (in-app; notification in M7); new period copies previous limits, no rollover; budget history per month and category (6-month chart); my-share rule (BUD-07) using `myShare`; optional group budget (Office); Budget tab and BudgetLimits editor per mockups.

**User stories.** US-04 (Food 40,000, warned at 32,000). "As the owner, I see October: Rs 78,374 spent, Rs 156,626 left, Personal over by Rs 1,200, Rs 3,000 unassigned." "As the owner, I switch to a 21st–20th salary cycle."

**Technical tasks.** UZeeCore: `BudgetPeriod` (calendar month / salary cycle, time-zone aware, clamping start day to month length), `BudgetCalculator`, `ThresholdEvaluator`. UZeeData: migration v4 (budgets, budget limits, budget settings), history queries. UZeeUI: Budget, BudgetLimits, category drill-down.

**Dependencies.** M3 accepted (categories). Uses `myShare` from M2; full split data arrives in M5, where BUD-015/016 are re-run as integration tests.

**Acceptance criteria.**
1. October sample: total Rs 235,000, spent **Rs 78,374**, left **Rs 156,626**, 33% used, unassigned **Rs 3,000**, Personal over by **Rs 1,200**.
2. Transfers, loan movements and settle-ups never count as spending; USD expenses convert at the table rate.
3. Warning fires once at ≥ threshold, alert once at > 100%, both re-evaluated after edits and deletes.
4. Salary-cycle boundaries correct for 21st–20th, short months, leap year and time-zone changes.
5. Budget history shows September and the 6-month record "kept 5 of 6, Aug over".

**Test cases.** BUD-001…022.

**Risks.** Period confusion when switching calendar month ↔ salary cycle mid-month → switching applies from the next period; current period shown with a note. Rounding of percentages → basis points half-up from exact minor units (DATA_MODEL), one display rule.

**Extra DoD.** Financial checklist items "budget calculations", "monthly totals", "category totals" covered and passing.

---

## M5 — People, loans & Splitwise-style splitting (0.5.0)

**Objective.** Clear, always-computed picture of who owes whom across loans and shared expenses, with settle up and simplify.

**Features.** People tab (one record per person); person detail combining loans and shared expenses (AUD-22); loans (lent/borrowed, person or institution, interest optional simple, due date, status Open/Partially paid/Settled/Written off); repayments linked to account transactions; lend/borrow creates transaction + loan together; fast entry of existing balances; groups (name, icon, members, default method, optional currency); split editor with four quick options — **Equally, Exact amounts, Percentages, Shares** — plus Paid by me / another member / several payers (AUD-08); expenses paid by someone else (no account movement, my share still spending); shared income (my share is income); balances per person, per group, overall; settle up (full/partial, any account); simplify debts within a group (S); group activity feed and monthly totals (S).

**User stories.** US-05 (lend Usama 20,000, he repays 5,000), US-08 (Office 50/50, settle at month end). "As the owner, I record that my office partner paid the electricity bill." "As the owner, I see Owed to you Rs 35,000 · You owe Rs 88,000."

**Technical tasks.** UZeeCore: `SplitCalculator` (remainder minor units allocated deterministically so shares always sum to the total), `BalanceLedger` (person/group/overall), `DebtSimplifier` (greedy max-creditor/max-debtor, net preserved), `LoanCalculator` (remaining, status, simple interest). UZeeData: migration v5 (people, loans, loan payments, groups, members, split shares, settlements). UZeeUI: People, Person, Group, Split, Settle up, Lend/Borrow/Repay sheets.

**Dependencies.** M4 accepted.

**Acceptance criteria.**
1. Office group October: **you owe Office partner Rs 9,800**; whole-group spend Rs 76,000.
2. Usama owes you **Rs 25,000**; Bilal Rs 10,000; Ammi you owe Rs 75,000; Ali you owe Rs 3,200; Sara settled.
3. Overall: Owed to you **Rs 35,000**, You owe **Rs 88,000**; every figure computed, none typed.
4. Split totals must equal the expense before Save is enabled; rounding remainders never lose or create a paisa.
5. Settle up Rs 9,800 from HBL zeroes the Office balance, reduces HBL, is not spending.
6. Budget re-check with real splits: October spent still Rs 78,374 (BUD-003 re-run as SPL-016).

**Test cases.** LOAN-001…012, SPL-001…020.

**Risks.** Mixed-currency group balances ($250 reimbursement) → each share stored in its own currency, converted for display at table rate, footnoted. Editing an old split after settlement → balances recomputed; settlement stays as recorded.

**Extra DoD.** Financial checklist item "loan balances" covered; all SPL money tests run on Linux core job.

---

## M6 — Bills, subscriptions, kameti & car installment (0.6.0)

**Objective.** One Bills & subscriptions hub where every recurring obligation and plan is tracked and can be marked paid, skipped or snoozed.

**Features.** Recurring items (REC-01 types and frequencies, fixed or estimated amount, optional split, end date); subscription details (service, renewal, status Active/Paused/Cancelled, price history); recurring income (salary $1,875 on the 21st, reimbursement varies); **hub** (REC-07) listing bills, subscriptions, kameti and car installment with progress, income, paused/cancelled, monthly and yearly totals — kameti and car installment have no separate screens; Mark paid (amount editable, account, date) / Skip / Snooze from the hub and Home (Calendar and notification in M7, REC-08); kameti (contributions, payouts, figure mismatch note); installment loan schedule (LOAN-06).

**User stories.** US-07 (confirm Netflix when due). "As the owner, I see kameti 5 of 12 and car installment 15 of 36 in the hub." "As the owner, I mark the gas bill paid at the actual amount."

**Technical tasks.** UZeeCore: `RecurrenceRule` (weekly, monthly with day clamping, quarterly, yearly incl. 29 Feb, custom N days/months), `OccurrenceGenerator`, `KametiSchedule`, `InstallmentSchedule`, `SubscriptionTotals`. UZeeData: migration v6 (recurring items, subscription details, price history, kameti, kameti events, installment schedules, occurrences). UZeeUI: Bills hub, Subscription detail, MarkPaid sheet.

**Dependencies.** M5 accepted (splits on recurring items, installment is a loan).

**Acceptance criteria.**
1. Subscriptions: 6 active, **Rs 14,065 / month**, **Rs 168,780 / year**; Amazon Prime Video listed as cancelled and excluded.
2. Kameti: contributed Rs 80,000 of Rs 240,000 (4 of 12), October #5 due 15 Oct, payouts Rs 300,000 → note "Check figures with the committee".
3. Car installment: #15 of 36 due 10 Oct, remaining Rs 990,000 (22 left), ends Jul 2028.
4. Mark paid posts a linked transaction once (no duplicates on double tap), advances the next due date; Skip advances without a transaction; Snooze moves by 1 day.
5. Gas bill (due 5 Oct) shows Overdue on 6 Oct.

**Test cases.** REC-001…015, SUB-001…006, KAM-001…006, LOAN-020…023.

**Risks.** Kameti figures unconfirmed (AS-04) → app shows mismatch note, doesn't block. Duplicate posting on repeated taps → idempotent occurrence id with unique constraint.

**Extra DoD.** Financial checklist items "recurring transactions", "installments", "yearly totals" covered.

---

## M7 — Calendar & reminders (0.7.0)

**Objective.** Every dated obligation appears on the calendar and produces one reminder at the right local time, robust to date and time-zone edge cases.

**Features.** Month calendar with dots/badges per type (CAL-01); day list with status Due/Paid/Overdue/Upcoming (CAL-02); custom events and reminders incl. non-money, with repeat (CAL-03); lead time and time of day, global default 1 day before 10:00, per-item override (CAL-04); one reminder per occurrence, overdue highlighted, no nagging (CAL-05); notification actions **Mark paid**, **Snooze 1 day**, **Open**; option to hide amounts in notifications; scheduler respecting the 64-pending cap, refreshed on launch, on change, on time-zone change and in background; loan due and follow-up reminders (LOAN-07), settle-up reminders (SPL-11), budget threshold notifications; optional EventKit export to a user-chosen calendar, UZee updates/deletes only its own events (CAL-06); permission requests only on first use.

**User stories.** US-06 (car installment and kameti on the calendar with reminders). "As the owner, I mark Netflix paid from the notification." "As the owner, I travel to Dubai and my reminders still fire at 10:00 local."

**Technical tasks.** UZeeSystem: `NotificationScheduler` (pure planning function in UZeeCore + thin UNUserNotificationCenter adapter), notification categories/actions, `CalendarExporter` (EventKit, stored external identifiers), time-zone/significant-time-change observers, BGAppRefresh task. UZeeData: migration v7 (financial events, reminders, export mappings).

**Dependencies.** M6 accepted.

**Acceptance criteria.**
1. October 2026 grid starts on Thursday and shows all 18 dataset items on the right days with the right statuses.
2. All section-20 scenarios (TEST_PLAN §5) pass: create, modify, delete, repeat, monthly bill, subscription renewal, loan due, overdue, permissions granted/denied, device time change, time-zone change, month/year boundaries, leap years.
3. Never more than 64 pending; the nearest occurrences are always the scheduled ones.
4. Denying notification or calendar permission leaves the in-app calendar fully working with an explanatory note.
5. Notification "Mark paid" posts exactly one transaction.

**Test cases.** CAL-001…026.

**Risks.** Simulator cannot fully reproduce lock-screen actions → manual device tests CAL-020/021. Background refresh not guaranteed → refresh on every launch and foreground.

**Extra DoD.** Manual device checklist for notifications and EventKit signed off on the owner's iPhone.

---

## M8 — Home dashboard & reports (0.8.0)

**Objective.** Opening the app answers "how much do I have, how much budget is left, what is due before salary" (OBJ-1), and reports explain the past.

**Features.** Home: Available balance (with USD footnote), Budget left, Spent this month vs last month same point; alert strip (overdue, over budget, large spend); Upcoming next 7 days with Mark paid; Owed to me / I owe; "Until next salary" forecast; category donut; Shared card with top groups (DSH-01…07). Reports: spending by category, income vs expenses (6 months), budget performance, subscriptions and recurring cost, owed/owing per person, group/person balance report (Office settlement), account balances over time and cash-flow trend (S); every report exportable to PDF; CSV export of transactions and other entities (DATA-03); footnote "Your shares only · transfers excluded · USD at $1 = Rs 280".

**User stories.** US-01. "As the owner, I see Rs 87,050 due before my salary on 21 Oct and Rs 397,750 left after bills." "As the owner, I export September's report as a PDF."

**Technical tasks.** UZeeCore: `ForecastCalculator`, `ReportAggregator` (month/range/year). UZeeData: aggregate SQL with indexes, CSV writer (RFC 4180, UTF-8, decimal strings), PDF renderer (UIGraphicsPDFRenderer/ImageRenderer). UZeeUI: Home, Reports, Swift Charts with accessibility summaries.

**Dependencies.** M7 accepted.

**Acceptance criteria.**
1. Home on 6 Oct sample: Available **Rs 484,800**, Budget left **Rs 156,626**, Spent **Rs 78,374** (Rs 9,800 less than Sep at the same point), Owed to you Rs 35,000, You owe Rs 88,000.
2. Until next salary: 15 days, due **Rs 87,050**, left after bills **Rs 397,750**.
3. Upcoming: Internet 8 Oct, Car installment 10 Oct, Netflix 12 Oct; gas bill in the alert strip.
4. September report: income Rs 560,000, spending Rs 231,565, net +Rs 328,435; category figures match the dataset.
5. PDF and CSV exports open in Files and contain the same totals as the screen.

**Test cases.** DSH-001…011, RPT-001…013.

**Risks.** Forecast double-counting items already paid → forecast uses unpaid occurrences only (tested). Chart performance → aggregation in SQL.

**Extra DoD.** Exported sample PDF attached to the milestone report.

---

## M9 — Ask UZee voice & Siri (0.9.0)

**Objective.** Ask money questions and record entries in one sentence, on-device, always with a confirmation card.

**Features.** App Intents + App Shortcuts ("Hey Siri, ask UZee …"), in-app mic and typed input, Action Button / Control Center / Lock Screen control (VOX-01); English (VOX-02); answers from local data (VOX-03); create expense, income, transfer, loan, repayment, reminder, event (VOX-04); follow-up questions for missing fields (VOX-05); matching people/accounts/categories with "create new person" offer (VOX-06); editable confirmation card, nothing saved without confirm (VOX-07); Apple Foundation Models with guided generation into typed `VoiceCommand`; unavailable state with fixed Siri commands and an explanation (VOX-08); amount phrases ("20k", "1.5 lakh", "$20").

**User stories.** US-09 ("how much do I owe my mother?" → Rs 75,000, same as People). PRD example: "I sent 20k PKR to a friend…" → "What's your friend's name?" → "Usama" → confirm Lent Rs 20,000 to Usama from Easypaisa.

**Technical tasks.** UZeeSystem: `VoiceParser` (Foundation Models session, `@Generable` command schema), `IntentHandlers`, entity resolvers. UZeeCore: deterministic `AmountPhraseParser`, `QueryAnswerer` (reuses M4–M8 calculators so voice and screens never disagree). UZeeUI: Voice screen and card.

**Dependencies.** M8 accepted. M0 spike result on free-account capabilities. Apple Intelligence on the owner's iPhone.

**Acceptance criteria.**
1. Every VOX-03 question returns the same number as the matching screen for the sample data.
2. The Usama flow completes in ≤ 3 voice turns and saves only after Save on the card.
3. With Apple Intelligence off, the app explains why and fixed commands still work.
4. Answer starts ≤ 3 s after the question ends on the owner's iPhone (PRF-04).

**Test cases.** VOX-001…015.

**Risks.** Model output varies → parsing via guided generation into a typed schema, deterministic validation after; a fixed set of 50 sample utterances run as an evaluation suite (VOX-014), pass rate reported honestly. Free Apple ID limits on Siri → fall back to in-app mic; if paid account needed, owner decides (moves to REQUIRED).

**Extra DoD.** Voice evaluation report (utterances, pass/fail) in the milestone report.

---

## M10 — Data safety: Face ID lock, backup/restore, PDF statement import, onboarding (0.10.0)

**Objective.** Data is protected, recoverable and easy to bring in.

**Features.** Optional Face ID/passcode lock with timeout; app-switcher privacy cover when lock is on (SET-01/02); encrypted backup file (AES-GCM, key from password via PBKDF2/HKDF, password never stored) via Files/iCloud Drive, including attachments; restore with validation, summary and automatic safety copy (DATA-02, §13); pre-migration safety copy (DATA-05); PDF statement import into a chosen account with per-bank readers, review screen (edit, exclude, suggested category), duplicate detection, past and monthly imports (IMP-01…06), CSV import (IMP-07, S); receipt reading of amount, date, merchant with Vision (AI-02, S); onboarding: base currency, salary day, suggested accounts (ACC-06), import recommendation (IMP-05), optional Face ID, sample-data option; Settings screens for security, data and preferences (SET-03).

**User stories.** US-10 (import HBL statement and review), US-11 (restore on a new phone).

**Technical tasks.** UZeeData: `BackupService` (versioned format header, KDF params, AES-GCM, zip of DB snapshot + attachments), `RestoreService`, `StatementReader` protocol + one reader per supplied bank sample, `DuplicateDetector`. UZeeSystem: `AppLock` (LocalAuthentication), scene-phase privacy overlay, Vision receipt reader.

**Dependencies.** M9 accepted. **Owner supplies one sample statement PDF per bank** (HBL, Meezan, Easypaisa, NayaPay, SadaPay, Wise, others) with personal data redacted or kept off the repo (test fixtures stored outside git or synthesised from the layout).

**Acceptance criteria.**
1. Backup → wipe → restore reproduces every record and attachment (counts and totals equal); wrong password and tampered file are rejected without touching data.
2. Lock on: app requires Face ID after timeout; app switcher shows no amounts.
3. Import of each supplied bank sample produces correct rows; duplicates flagged; nothing saved before confirm; unsupported PDF shows a clear message.
4. Migration from every earlier schema version (v1…v9 fixtures) succeeds with a safety copy.
5. Onboarding can be completed or skipped; sample-data choice respects PRV-04.

**Test cases.** SEC-001…008, DATA-020…026, IMP-001…009, UI-030…034.

**Risks.** Bank PDF variety → readers only for supplied samples, clear unsupported message (IMP-06). Real statements contain personal data → never committed; tests use synthesised PDFs with the same layout. Lost backup password → unrecoverable by design; warned at creation.

**Extra DoD.** Security review checklist (TEST_PLAN §8) completed for this milestone.

---

## M11 — iPad, dark mode, accessibility & performance polish (0.11.0)

**Objective.** The app feels native and fast on iPhone and iPad, in light and dark, for every user.

**Features.** iPad NavigationSplitView polish, portrait/landscape, Split View and Stage Manager sizes, keyboard shortcuts for add/search; full dark mode review against mockups; Dynamic Type to AX5; VoiceOver labels and chart summaries; colour never the only signal; WCAG AA contrast; Reduce Motion; performance with 10,000 transactions; alerts polish (DSH-07).

**User stories.** "As the owner, I use UZee on an iPad in landscape with the sidebar." "As a VoiceOver user, I hear 'Personal, over budget by Rs 1,200'."

**Technical tasks.** Snapshot tests across size classes and appearances; Accessibility Inspector audit; Instruments (Time Profiler, Hitches) runs; 10k-transaction performance fixture; query index review.

**Dependencies.** M10 accepted.

**Acceptance criteria.** PRF-01 cold launch ≤ 1.5 s, PRF-02 smooth scrolling, PRF-03 reports ≤ 1 s, all on the owner's iPhone with 10k transactions; zero accessibility audit errors on core screens; iPad layouts approved by the owner.

**Test cases.** UI-040…047, A11Y-001…006, PRF-001…005.

**Risks.** Performance targets missed on large data → measured early with fixture, pagination and indexes.

**Extra DoD.** Performance numbers recorded in BUILD_HISTORY.

---

## M12 — Release preparation (0.12.0 → 1.0.0)

**Objective.** A stable, reviewed v1 the owner relies on daily; TestFlight once a paid Apple Developer account exists.

**Features / steps.** End-of-development feature review (§28: high value/low effort, high value/high effort, optional polish, future version) and the owner's decision; Release Readiness Review (§29) producing RELEASE_READINESS report; full regression on device; if the paid account exists: App ID, distribution signing, App Store Connect record, privacy details, screenshots, TestFlight build (§30, DEPLOYMENT_GUIDE §3); otherwise 1.0.0 is installed with the free Apple ID and TestFlight steps are deferred.

**User stories.** "As the owner, I get a v1 build with a written readiness report and know exactly what is and isn't verified."

**Dependencies.** M11 accepted. Paid Apple Developer Program for TestFlight. Release (non-beta) Xcode for uploads.

**Acceptance criteria.** All REL-001…018 items pass or have an owner-approved exception; no open Critical/High bugs; owner's explicit approval to deploy (§30).

**Test cases.** REL-001…018, plus the full suite.

**Risks.** Paid account not yet bought → TestFlight deferred, no release blocker for personal use. App Review rules for finance apps → privacy labels "Data Not Collected", no network.

**Extra DoD.** Release readiness report, release notes and tag `v1.0.0` on `main`.
