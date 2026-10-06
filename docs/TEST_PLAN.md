# UZee — Test Plan

| | |
|---|---|
| Version | 0.1 (2026-10-06) |
| Status | Draft, awaiting user approval |
| Related | MILESTONE_PLAN.md, TEST_REGISTRY.md, BUG_REGISTRY.md, BUILD_HISTORY.md |

Guiding rule (master prompt §26): data integrity and correct financial calculations come before everything else. A test is never reported as passed unless it was actually run on the stated build.

## 1. Strategy

| Level | Tool | Where the code lives | Runs on | What it covers |
|---|---|---|---|---|
| Unit | Swift Testing (`@Test`, parameterised) | UZeeCore tests | Linux CI job + macOS CI job + owner's Mac | Money, rounding, rates, balances, budgets, budget periods, splits, debt simplification, loans, recurrence rules, kameti, installments, forecast, report aggregation, notification planning, amount phrases. **Priority 1** |
| Integration | Swift Testing with in-memory / temp-file GRDB database | UZeeData, UZeeSystem tests | macOS CI (iOS simulator) | Migrations, repositories, transactions (atomicity), sample fixture, search, purge, backup/restore, CSV/PDF export, statement readers, scheduler adapter with a fake notification center |
| UI | XCTest UI tests (XCUITest) | UZeeUITests | macOS CI (iPhone + iPad simulators) | Smoke (SMK), main flows per milestone, launch arguments `-uiTesting -sampleData -fixedNow 2026-10-06T12:00:00+05:00` for deterministic dates |
| Snapshot | Image snapshots of SwiftUI views (light/dark, Dynamic Type sizes) | UZeeUI tests | macOS CI | Components and key screens against approved mockups; diffs reviewed, never auto-accepted |
| Manual device | Checklist in TEST_REGISTRY (Level = Manual) | — | Owner's iPhone 17 Pro Max (iOS 27), iPad if available | Install, Face ID, notifications on lock screen, EventKit, Siri/Action Button, voice latency, performance with 10k rows, real PDF statements |

Test IDs: `PREFIX-nnn` (3 digits). PRD requirement IDs use 2 digits (`TXN-01`); test IDs use 3 (`TXN-001`), so the two never clash. Prefixes: SMK, REG, BUG (bug reproductions are REG tests linked to a BUG id), ENV, UI, ACC, TXN, CUR, CAT, ATT, BUD, LOAN, SPL, REC, SUB, KAM, CAL, DSH, RPT, VOX, DATA, IMP, SEC, A11Y, PRF, REL.

Each automated test's name carries its ID, e.g. `@Test("BUD-003 October spent, left and percent")`, so CI output maps straight to the registry.

Determinism: all code takes time from an injected `Clock`/`now`, the calendar and time zone from an injected `Calendar`; tests never depend on the real date, the device time zone or the network.

## 2. Coverage required per milestone (§14)

Every milestone's tests cover: happy path · boundary conditions · invalid input · empty data · persistence (relaunch) · error handling · integration with earlier modules. MILESTONE_PLAN lists the IDs; TEST_REGISTRY holds them permanently.

## 3. Sample data as the oracle

Expected values come from docs/mockup-dataset.md ("today" Tue 6 Oct 2026, Asia/Karachi, $1 = Rs 280). Key anchors:

| Anchor | Value |
|---|---|
| Available balance (9 accounts) | Rs 484,800 = Rs 300,000 + $660 |
| October spent (my share, 1–6 Oct) | Rs 78,374 |
| Budget October | total 235,000 · left 156,626 · 33% · unassigned 3,000 · Personal over by 1,200 |
| Office group | you owe Office partner Rs 9,800 · group spend Rs 76,000 |
| People totals | owed to you Rs 35,000 · you owe Rs 88,000 |
| Until next salary (21 Oct) | 15 days · due Rs 87,050 · left after bills Rs 397,750 |
| Subscriptions | Rs 14,065 / month · Rs 168,780 / year |
| Transfer | $500 → Rs 139,350 at 278.70 (Rs 650 less than at 280) |
| September report | income 560,000 · spending 231,565 · net +328,435 |

If the dataset changes, the tests change in the same commit and CHANGELOG records why.

## 4. Financial calculation testing (§18)

All money uses `Money` (Int64 minor units + currency); one rounding function (half-up, i.e. halves round away from zero) applied only at conversion and allocation. CI fails if `Double`/`Float` appears in money types.

| §18 item | How tested | Test IDs |
|---|---|---|
| Addition | same-currency sums exact; 1,000 × Rs 0.01 = Rs 10.00 | CUR-001 |
| Subtraction | results below zero, over-budget amounts | CUR-002, BUD-005 |
| Decimal precision | no float; conversion and splits keep every paisa | CUR-004, CUR-005, SPL-008 |
| Currency formatting | Rs / $ symbols, grouping, ≈ secondary line, negatives | CUR-006, UI-005 |
| Negative values | negative results, refunds, adjustments | CUR-002, TXN-005, ACC-004 |
| Large amounts | Rs 10 billion sums, Int64 overflow refused | CUR-007 |
| Zero values | zero identity, zero amount refused, no divide-by-zero | CUR-008, BUD-022 |
| Refunds | reduce category spending, not income | TXN-005, BUD-016 |
| Transfers | excluded from income/expense; real rate stored | TXN-003, TXN-004, CUR-009, CUR-010 |
| Loan balances | partial, full, overpayment, write-off, interest | LOAN-002…010 |
| Installments | 36-month schedule, remaining | LOAN-020…023 |
| Budget calculations | spent, left, %, unassigned, thresholds, periods | BUD-001…022 |
| Recurring transactions | next due, day clamping, mark paid once | REC-001…015 |
| Monthly totals | Oct spent, subscriptions monthly | BUD-003, SUB-001, RPT-001 |
| Yearly totals | subscriptions yearly, 6-month sums | SUB-001, RPT-010 |
| Category totals | Office 38,000 · Transport 16,367 · Food 15,470 … | BUD-004, TXN-023, RPT-002 |
| Splits (UZee addition) | equal/exact/%/shares, remainders, multi-payer | SPL-001…010 |

Property tests (parameterised): for random splits the shares always sum to the total; for random ledgers the sum of all group balances is zero; simplify never changes a member's net.

## 5. Calendar and reminder testing (§20)

| §20 scenario | Test IDs |
|---|---|
| Reminder creation | CAL-004, CAL-005 |
| Reminder modification | CAL-006 |
| Reminder deletion | CAL-007 |
| Repeating reminders | CAL-008 |
| Monthly bills | CAL-010, REC-006 |
| Subscription renewal | CAL-011, SUB-006 |
| Loan due dates | CAL-012 |
| Overdue payments | CAL-014, REC-009 |
| Notification permissions | CAL-015 |
| Calendar permissions | CAL-017, CAL-018 |
| Permission denial | CAL-016, CAL-017 |
| Changed device time | CAL-019 |
| Changed time zone | CAL-020, CAL-021 (DST zone) |
| Month boundaries | CAL-022, BUD-018 |
| Year boundaries | CAL-023 |
| Leap years | CAL-024, BUD-019 |
| 64 pending notification cap (UZee addition) | CAL-025 |
| Notification actions Mark paid / Snooze / Open | CAL-026 |

Scheduling logic is a pure function in UZeeCore (`plan(items, now, calendar, timeZone) -> [PlannedNotification]`) so most cases run as unit tests; the UNUserNotificationCenter adapter is tested with a fake; lock-screen behaviour is tested manually on the device.

## 6. Test-before-every-build gate (§17)

No build is installed, shared or recorded as delivered until this gate is run and reported:

| Step | Suite | Blocks build if failing |
|---|---|---|
| 1 | Smoke tests SMK-001…012 (all that exist) | Yes |
| 2 | Feature tests of the current milestone | Yes, unless the owner approves a known issue |
| 3 | All REG tests (bug regressions) | Yes |
| 4 | Critical integration tests: all CUR, BUD-003, SPL-004, SPL-013, DSH-007, DATA-020 once they exist | Yes |
| 5 | Remaining registry tests (earlier milestones) | Critical/High failures block; Medium/Low reported |

A failure is never hidden. It is reported in BUILD_HISTORY and in the message to the owner with: failed test · expected · actual · likely reason · severity · block build yes/no. Critical regression failures block the build.

Severity: **Critical** wrong money/balance, data loss, crash on launch · **High** core flow blocked, wrong reminder date · **Medium** wrong display/format with a workaround · **Low** cosmetic.

## 7. How tests run

| Where | Command / trigger | Suites |
|---|---|---|
| CI `core-linux` (ubuntu) | every push and PR: `swift test --package-path Packages/UZeeCore` | UZeeCore unit tests |
| CI `ios` (macOS runner, newest stable Xcode) | PRs to `development`/`main` and pushes to them: `xcodebuild test -scheme UZee -testPlan All -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)'` (exact device names pinned in the workflow from `xcrun simctl list`) | Unit + integration + UI + snapshot; `.xcresult` uploaded as an artifact |
| Owner's Mac (Xcode 27 beta) | Product → Test (⌘U) or the same `xcodebuild` command | Same as CI; confirms the beta SDK |
| Owner's iPhone | Manual checklist from the registry (Level = Manual) at the end of each milestone, ≈ 15–30 min, steps written exactly | Device-only tests |

Merging to `development` requires both CI jobs green. Test plans: `Smoke`, `Milestone`, `Regression`, `All` (Xcode test plans) so the gate in §6 can be run in parts.

## 8. Security and privacy checks (each milestone that touches data, full at M10/M12)

No amounts, names or notes in logs (SEC-004); no network calls (SEC-005); Data Protection on DB, attachments, backups (ENV-005, SEC-008); backup password never stored (SEC-006); permissions requested only at first use (PRV-03); sample data never mixed with real data (DATA-004).

## 9. Honest reporting format

Every test run reported to the owner or recorded in BUILD_HISTORY uses this block:

```
BUILD: 0.2.0 (14)          DATE: 2026-mm-dd
RUN ON: CI core-linux #123, CI ios #45 (iPhone 17 Pro sim iOS 26.x, iPad sim), owner's iPhone (manual)
SUITES: Smoke, M2 feature, Regression, Critical integration
TOTAL: 58   PASS: 56   FAIL: 1   SKIPPED/NOT RUN: 1
FAILED:
  TXN-011 Date at month end in another time zone
    expected: stays in October; actual: shown in November
    likely reason: month bucketing used device time zone
    severity: High   blocks build: yes
NOT RUN:
  SMK-001 on device (iPhone not connected) — will run before install
REGRESSIONS (previously passing, now failing): none
```

Rules: "Not run" is a status, never "Pass"; a test run only in the simulator says so; manual tests list who ran them and on what device; the registry's ACTUAL RESULT, STATUS and BUILD are updated after each run; PROJECT_STATE totals (TOTAL/PASSING/FAILING) are updated from the same numbers.
