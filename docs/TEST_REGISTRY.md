# UZee — Test Registry (permanent)

| | |
|---|---|
| Version | 0.1 (2026-10-06), seeded from MILESTONE_PLAN v0.1 |
| Totals | 313 tests registered · 21 run · 21 pass (6 partial) · 0 fail · as of build 0.1.0 (2) |
| Oracle | docs/mockup-dataset.md: today Tue 6 Oct 2026, Asia/Karachi, $1 = Rs 280, spending = my share |

## Rules

- Tests are **never deleted**. A test that no longer applies is marked `Retired` with the date, reason and the owner's approval; it stays in this file.
- Every test has an ID, module, title and expected result. Core tests use the full §12 format; others use the compact table and get the full format when first run.
- After every run, ACTUAL RESULT, STATUS (`Not run` · `Pass` · `Pass (partial)` (what ran passed but some steps are not covered yet; ACTUAL RESULT says which) · `Fail` · `Blocked` · `Retired`) and BUILD are updated. Totals at the top are updated with them.
- Level: **U** unit (UZeeCore, also Linux) · **I** integration (GRDB / system adapters) · **UI** XCUITest/snapshot · **M** manual on device.
- Bug regressions are added as `REG-nnn` (linked to `BUG-nnn` in BUG_REGISTRY) and run before every build.

## Index

| Prefix | Module | IDs | Milestone | Format |
|---|---|---|---|---|
| SMK | Smoke | 001–012 | M0–M3 | Full |
| ENV | Environment & skeleton | 001–008 | M0 | Compact |
| UI | Navigation, design system, onboarding, iPad | 001–012, 030–034, 040–047 | M1, M10, M11 | Compact |
| DATA | Sample mode, Recently Deleted, backup, migration | 001–004, 010–014, 020–026 | M1, M3, M10 | Compact |
| CUR | Money and currency | 001–012 | M2 | Full |
| ACC | Accounts | 001–008 | M2 | Full |
| TXN | Transactions | 001–015 (full), 020–028 (compact) | M2, M3 | Mixed |
| CAT / ATT | Categories, tags, payees / attachments | CAT 001–008, ATT 001–004 | M3 | Compact |
| BUD | Budgeting | 001–022 | M4 | Full |
| LOAN | Loans / installment plans | 001–012 (full), 020–023 (compact) | M5, M6 | Mixed |
| SPL | Splitting and groups | 001–020 | M5 | Full |
| REC / SUB / KAM | Recurring, subscriptions, kameti | REC 001–015, SUB 001–006, KAM 001–006 | M6 | Compact |
| CAL | Calendar and reminders | 001–026 | M7 | Compact |
| DSH / RPT | Dashboard, reports, export | DSH 001–011, RPT 001–013 | M8 | Compact |
| VOX | Voice and Siri | 001–015 | M9 | Compact |
| SEC / IMP | Security, statement import | SEC 001–008, IMP 001–009 | M10 | Compact |
| A11Y / PRF | Accessibility, performance | A11Y 001–006, PRF 001–005 | M11 | Compact |
| REL | Release readiness | 001–018 | M12 | Compact |
| REG | Bug regressions | none yet | — | Full |

Common fields for every full-format test below unless stated: **ACTUAL RESULT:** — · **STATUS:** Not run · **BUILD:** —

---

## 1. Smoke tests (SMK) — full format

**TEST ID:** SMK-001 · **MODULE:** App · **TITLE:** Application installs
- PRECONDITIONS: Clean simulator (iPhone and iPad) or owner's iPhone paired, Developer Mode on, no previous UZee install.
- STEPS: 1. Build and run scheme UZee from Xcode (device) or `xcodebuild test` (simulator). 2. Look at the Home Screen.
- EXPECTED RESULT: Install succeeds with no signing or provisioning error; UZee icon appears.
- ACTUAL RESULT: 2026-10-06: installed from Xcode 27 beta (free Apple ID, Personal Team) on owner's iPhone 17 Pro Max, iOS 27.0; icon appeared; one-time Trust step done. CI simulators install via test runner (run #5). · STATUS: Pass · BUILD: 0.0.1 (1)
- NOTES: Level UI + M. From M0. On device also tests "Trust developer" first-run step.

**TEST ID:** SMK-002 · **MODULE:** App · **TITLE:** Application launches
- PRECONDITIONS: SMK-001 passed.
- STEPS: 1. Tap the UZee icon (or `XCUIApplication().launch()`). 2. Wait for the first screen.
- EXPECTED RESULT: First screen appears (M0: "UZee 0.0.1 (1)" placeholder; M1+: Home tab) with no alert or error banner.
- ACTUAL RESULT: Launch screen "UZee · 0.0.1 (1) · Database ready" on owner's iPhone; CI run #5 passed on iPhone 17 Pro and iPad Pro 13-inch (M5) simulators, iOS 26.5. · STATUS: Pass · BUILD: 0.0.1 (1)
- NOTES: Level UI + M. From M0.

**TEST ID:** SMK-003 · **MODULE:** App · **TITLE:** No crash on launch
- PRECONDITIONS: SMK-001 passed.
- STEPS: 1. Cold launch 5 times (terminate between launches). 2. Check app state after 5 s each time. 3. Check Xcode Organizer / device crash logs.
- EXPECTED RESULT: App is `runningForeground` every time; no crash report.
- ACTUAL RESULT: CI run #5: one cold launch per simulator, `runningForeground`, no crash; owner's iPhone launched without crash. The 5× cold-launch loop and crash-log check are not automated yet. · STATUS: Pass (partial) · BUILD: 0.0.1 (1)
- NOTES: Level UI + M. From M0. NFR-07.

**TEST ID:** SMK-004 · **MODULE:** Data · **TITLE:** Database initializes
- PRECONDITIONS: Fresh install (no database file).
- STEPS: 1. Launch. 2. Inspect Application Support/UZee/uzee.sqlite via the debug info screen or integration test hook. 3. Read `grdb_migrations` and the file protection attribute.
- EXPECTED RESULT: File exists; all migrations up to the build's latest are recorded once; protection = `completeUntilFirstUserAuthentication`; WAL mode on.
- ACTUAL RESULT: CI run #5: "Database ready" shown with the in-memory database; migrations covered by ENV-004. On-disk file, WAL mode and protection attribute not checked yet (ENV-005, needs a debug info screen). · STATUS: Pass (partial) · BUILD: 0.0.1 (1)
- NOTES: Level I + UI. From M0. Protection attribute only meaningful on device (ENV-005).

**TEST ID:** SMK-005 · **MODULE:** Navigation · **TITLE:** Main navigation loads
- PRECONDITIONS: App launched, sample data off.
- STEPS: 1. Read the tab bar. 2. Tap each tab.
- EXPECTED RESULT: Tabs Home, Activity, Budget, Calendar, People in this order plus a separate "+" button; each tab shows its title; iPad shows a sidebar with the same destinations.
- ACTUAL RESULT: 2026-10-07: tabs in order, each opens with its title (testSMK005_UI001_tabsInOrderAndOpen) in CI run #13 (iPhone 17 Pro sim, iOS 26.5) and on owner's Mac (iPhone 17 Pro Max sim, iOS 27). iPad sidebar not checked (UI-004 not run). · STATUS: Pass (partial) · BUILD: 0.1.0 (2)
- NOTES: Level UI. From M1.

**TEST ID:** SMK-006 · **MODULE:** Navigation · **TITLE:** Core screens open
- PRECONDITIONS: Sample data on.
- STEPS: Open each screen that exists in the build: Add sheet, Settings (M1); Accounts, Transfer (M2); Transaction detail, Recently Deleted (M3); Budget limits (M4); Person, Group, Split (M5); Bills & subscriptions hub, Subscription detail, Mark paid (M6); Calendar day (M7); Reports (M8); Voice (M9); Backup, Import, Onboarding (M10).
- EXPECTED RESULT: Each opens with its title, no error state, and a working Back/Close.
- ACTUAL RESULT: — · STATUS: Not run · BUILD: —
- NOTES: Level UI. From M1; list grows each milestone (never shrinks). 0.1.0 (2): Add sheet and Settings were opened and closed by UI-003 / UI-012 / DATA-001 tests, but not with sample data on and the Add sheet title is not checked, so not counted as run.

**TEST ID:** SMK-007 · **MODULE:** Transactions · **TITLE:** Basic transaction can be created
- PRECONDITIONS: Real mode, account "HBL" PKR opening Rs 10,000.
- STEPS: 1. Tap "+". 2. Enter 1500. 3. Category Utilities › Mobile. 4. Account HBL. 5. Save, confirm.
- EXPECTED RESULT: "Saved · Undo" toast; expense Rs 1,500 listed today; HBL balance Rs 8,500.
- ACTUAL RESULT: — · STATUS: Not run · BUILD: —
- NOTES: Level UI. From M2.

**TEST ID:** SMK-008 · **MODULE:** Transactions · **TITLE:** Transaction persists after restart
- PRECONDITIONS: SMK-007 done.
- STEPS: 1. Terminate the app. 2. Relaunch. 3. Open the list and HBL.
- EXPECTED RESULT: Expense Rs 1,500 with same date, category, account; HBL Rs 8,500.
- ACTUAL RESULT: — · STATUS: Not run · BUILD: —
- NOTES: Level UI. From M2.

**TEST ID:** SMK-009 · **MODULE:** Transactions · **TITLE:** Transaction can be edited
- PRECONDITIONS: SMK-008 done.
- STEPS: 1. Open the Rs 1,500 expense. 2. Change amount to 1650. 3. Save.
- EXPECTED RESULT: List shows Rs 1,650; HBL Rs 8,350; updatedAt changed, createdAt unchanged.
- ACTUAL RESULT: — · STATUS: Not run · BUILD: —
- NOTES: Level UI. From M2.

**TEST ID:** SMK-010 · **MODULE:** Transactions · **TITLE:** Transaction can be deleted
- PRECONDITIONS: SMK-009 done.
- STEPS: 1. Delete the Rs 1,650 expense. 2. Confirm. 3. Check list and HBL. 4. (M3+) open Recently Deleted.
- EXPECTED RESULT: Gone from list; HBL Rs 10,000; (M3+) present in Recently Deleted with "30 days".
- ACTUAL RESULT: — · STATUS: Not run · BUILD: —
- NOTES: Level UI. From M2; step 4 from M3.

**TEST ID:** SMK-011 · **MODULE:** App · **TITLE:** Application survives relaunch
- PRECONDITIONS: App installed; (M2+) at least one transaction.
- STEPS: Repeat 3×: launch → send to background → foreground → terminate → relaunch.
- EXPECTED RESULT: No crash; same data; migrations not re-run; no duplicate rows.
- ACTUAL RESULT: CI run #5: launch → terminate → relaunch once per simulator, no crash. 3× loop with background/foreground not automated yet. · STATUS: Pass (partial) · BUILD: 0.0.1 (1)
- NOTES: Level UI. From M0.

**TEST ID:** SMK-012 · **MODULE:** Transactions · **TITLE:** Invalid input is handled safely
- PRECONDITIONS: Add sheet open.
- STEPS: Try in turn: empty amount; 0; paste "abc"; 13+ integer digits; no account selected; transfer to the same account.
- EXPECTED RESULT: Save disabled or a clear message per case; nothing saved; no crash; entered values kept so the user can fix them.
- ACTUAL RESULT: — · STATUS: Not run · BUILD: —
- NOTES: Level UI. From M2.

---

## 2. M0 — Environment (compact)

| ID | Lvl | Title | Expected result | Status |
|---|---|---|---|---|
| ENV-001 | CI | CI `core-linux` runs UZeeCore tests | Job green; test count printed; any failure fails the job | Pass · 0.0.1 (1) · CI run #5 core-linux, 2 tests |
| ENV-002 | CI | CI `ios` builds app + packages and runs tests on iPhone and iPad simulators | Job green; `.xcresult` uploaded | Pass · 0.0.1 (1) · CI run #5: 7 package tests + 4 smoke tests on iPhone and iPad sims |
| ENV-003 | M | Local build on owner's Mac (Xcode 27 beta) | Build and ⌘U succeed with zero errors | Not run · build + run on device succeeded 2026-10-06; ⌘U not run locally yet |
| ENV-004 | I | Migration v1 on empty DB, then relaunch | Schema created once; second launch applies nothing | Pass · 0.0.1 (1) · MigrationTests (3) in CI run #5 |
| ENV-005 | M | DB file protection on device | Attribute = completeUntilFirstUserAuthentication | Not run |
| ENV-006 | UI | Version display | "0.0.1 (1)" equals Info.plist values | Pass · 0.0.1 (1) · CI run #5 + owner's iPhone shows "0.0.1 (1)" |
| ENV-007 | CI | Secret-pattern check | Fails on a planted fake key in a throwaway branch; passes on clean repo | Pass · 0.0.1 (1) · planted key failed locally, clean repo passes in CI run #5 |
| ENV-008 | M | Logger redaction | Interpolated amount/name shows `<private>` in Console | Not run |

## 3. M1 — Navigation, design system, sample mode (compact)

| ID | Lvl | Title | Expected result | Status |
|---|---|---|---|---|
| UI-001 | UI | Tab order | Home, Activity, Budget, Calendar, People + separate "+" | Pass · 0.1.0 (2) · unit + UI (smoke testSMK005_UI001, CI run #13 + owner's Mac) |
| UI-002 | UI | Per-tab navigation state | Push in Activity, switch to Budget and back → still pushed | Pass · 0.1.0 (2) · unit + UI (smoke testUI002, CI run #13 + owner's Mac) |
| UI-003 | UI | "+" from every tab | Add sheet opens from all 5 tabs; Close returns to same tab | Pass · 0.1.0 (2) · unit + UI (smoke testUI003, CI run #13 + owner's Mac) |
| UI-004 | UI | iPad sidebar | NavigationSplitView with the same 5 destinations + Add | Not run · iPad smoke not completed (CI run #14 stopped in setup, #16 timed out) |
| UI-005 | U | MoneyText formatting | `Rs 182,400`; `$520.00` with secondary `≈ Rs 145,600`; tabular digits | Pass · 0.1.0 (2) · unit (UZeeUI tests, CI run #13) |
| UI-006 | UI | Status never colour-only | Labels read "owes you", "you owe", "✓ Paid", "! Overdue" | Pass · 0.1.0 (2) · unit (UZeeUI tests, CI run #13) |
| UI-007 | U | Fixed category colours | Office #5856D6, Transport #007AFF, Food #FF9500, Personal #30B0C7, Utilities #FFCC00 (text #A07800), Subscriptions #FF2D55, Financial #00C7BE, Health #FF3B30, Income #34C759 | Pass · 0.1.0 (2) · unit (UZeeUI tests, CI run #13) |
| UI-008 | UI | Empty / loading / error states | Each component shows its state text and action | Not run |
| UI-009 | UI | Confirm sheet + Undo toast | Money action opens confirm; after save toast "Saved · Undo" for ≥ 4 s | Pass (partial) · 0.1.0 (2) · unit (UZeeUI tests, CI run #13); UI part with M2 money actions |
| UI-010 | UI | Light/dark snapshots | Components match approved snapshots in both appearances | Not run |
| UI-011 | UI | Components at AX5 text size | No clipped amounts; rows wrap | Not run |
| UI-012 | UI | Home toolbar | Mic and gear open Voice placeholder and Settings; no top segmented controls anywhere | Pass · 0.1.0 (2) · smoke testUI012, CI run #13 + owner's Mac |
| DATA-001 | UI | Sample mode banner | Banner "Sample data" on every tab while on | Pass · 0.1.0 (2) · smoke testDATA001, CI run #13 + owner's Mac |
| DATA-002 | I | Remove sample data | Only `isSample = 1` rows removed, in one transaction; real row counts unchanged | Pass (partial) · 0.1.0 (2) · mechanism tested with stand-in tables (UZeeData, CI run #13); real tables in M2 |
| DATA-003 | I | Real record while sample mode on | Saved as real, survives removal | Not run · needs content tables (M2) |
| DATA-004 | I | No mixing in totals | Totals in real mode exclude sample rows and vice versa | Not run · needs content tables (M2) |

---

## 4. M2 — Money and currency (CUR) — full format

**TEST ID:** CUR-001 · **MODULE:** Money · **TITLE:** Same-currency addition is exact
- PRECONDITIONS: none (pure unit test).
- STEPS: 1. Rs 0.10 + Rs 0.20. 2. Sum 1,000 × Rs 0.01. 3. Sum the six October category totals 38,000 + 16,367 + 15,470 + 6,200 + 1,500 + 837.20.
- EXPECTED RESULT: 1. Rs 0.30 (30 minor units). 2. Rs 10.00 exactly. 3. Rs 78,374.20, displayed "Rs 78,374".
- NOTES: Level U. §18 addition, precision.

**TEST ID:** CUR-002 · **MODULE:** Money · **TITLE:** Subtraction and negative results
- PRECONDITIONS: none.
- STEPS: 1. Rs 5,000 − Rs 6,200. 2. Rs 235,000 − Rs 78,374.20. 3. Format results.
- EXPECTED RESULT: 1. −Rs 1,200 shown as "−Rs 1,200" (with "over by Rs 1,200" wording where used). 2. Rs 156,625.80, displayed "Rs 156,626".
- NOTES: Level U. **Open point:** the dataset shows PKR totals in whole rupees (Rs 78,374, Rs 156,626) while DESIGN_SYSTEM says PKR shows decimals when non-zero (would give Rs 78,374.20). Expected values here follow the dataset; resolve before M2 and update both docs and these tests in the same commit.

**TEST ID:** CUR-003 · **MODULE:** Money · **TITLE:** Mixed-currency arithmetic refused
- PRECONDITIONS: none.
- STEPS: 1. Rs 100 + $1. 2. Compare Rs 100 with $1.
- EXPECTED RESULT: Throws `MoneyError.currencyMismatch`; no implicit conversion.
- NOTES: Level U.

**TEST ID:** CUR-004 · **MODULE:** Currency · **TITLE:** Conversion at the table rate
- PRECONDITIONS: Rate table USD = 280 PKR.
- STEPS: Convert $2.99, $20.00, $520.00, $660.00 to PKR.
- EXPECTED RESULT: Rs 837.20 · Rs 5,600.00 · Rs 145,600.00 · Rs 184,800.00.
- NOTES: Level U.

**TEST ID:** CUR-005 · **MODULE:** Currency · **TITLE:** Half-up rounding happens in one place
- PRECONDITIONS: none.
- STEPS: 1. Round 2.78705 to 2 places. 2. Round 2.785. 3. Round 2.78499. 4. Round −2.785. 5. Convert $0.01 at 278.705. 6. Search money code for any other rounding call.
- EXPECTED RESULT: 1. 2.79. 2. 2.79. 3. 2.78. 4. −2.79 (halves round away from zero). 5. Rs 2.79. 6. Only `Rounding.halfUp` is used.
- NOTES: Level U. Single rounding point per tech brief.

**TEST ID:** CUR-006 · **MODULE:** Currency · **TITLE:** Currency formatting
- PRECONDITIONS: Locale en, base PKR.
- STEPS: Format Rs 182,400; $520.00; −Rs 14,517; Rs 0; $2.99 with secondary line; Rs 1,000,000.
- EXPECTED RESULT: "Rs 182,400" · "$520.00" · "−Rs 14,517" · "Rs 0" · "$2.99" + "≈ Rs 837" · "Rs 1,000,000". Amounts always carry Rs or $.
- NOTES: Level U. AUD-04.

**TEST ID:** CUR-007 · **MODULE:** Money · **TITLE:** Large amounts and overflow
- PRECONDITIONS: none.
- STEPS: 1. Rs 9,999,999,999.99 + Rs 0.01. 2. Sum 10,000 × Rs 99,999,999. 3. Int64.max minor units + 1 minor unit.
- EXPECTED RESULT: 1. Rs 10,000,000,000.00. 2. Rs 999,999,990,000 exact. 3. Throws `MoneyError.overflow`; nothing saved; user message "Amount too large".
- NOTES: Level U.

**TEST ID:** CUR-008 · **MODULE:** Money · **TITLE:** Zero values
- PRECONDITIONS: none.
- STEPS: 1. Rs 0 + Rs 182,400. 2. Format Rs 0 and $0. 3. Percentage of Rs 0 limit.
- EXPECTED RESULT: 1. Rs 182,400. 2. "Rs 0", "$0.00". 3. Returns `nil` ("no limit"), never divides by zero.
- NOTES: Level U. Zero-amount transactions are refused in TXN-009.

**TEST ID:** CUR-009 · **MODULE:** Currency · **TITLE:** Transfer stores its own implied rate
- PRECONDITIONS: Accounts Wise (USD), HBL (PKR).
- STEPS: 1. Transfer sent $500.00, received Rs 139,350. 2. Read the stored rate. 3. Read the difference vs table rate.
- EXPECTED RESULT: Rate 278.70 stored as Decimal; recomputed received = Rs 139,350.00 exactly; note "Rs 650 less than at 280".
- NOTES: Level U + I. TXN-03, CUR-04.

**TEST ID:** CUR-010 · **MODULE:** Currency · **TITLE:** Changing the table rate does not rewrite history
- PRECONDITIONS: Sample data; CUR-009 transfer exists.
- STEPS: 1. Settings → rate 285. 2. Read available total and Wise. 3. Open the transfer.
- EXPECTED RESULT: Wise "$520.00 ≈ Rs 148,200"; available Rs 488,100; transfer still $500 → Rs 139,350 at 278.70. Reset to 280 → Rs 484,800.
- NOTES: Level I.

**TEST ID:** CUR-011 · **MODULE:** Currency · **TITLE:** PKR totals include USD at table rate
- PRECONDITIONS: Sample accounts loaded.
- STEPS: Read available balance and footnote.
- EXPECTED RESULT: Rs 484,800 (Rs 300,000 + $660 × 280) with footnote "USD at $1 = Rs 280".
- NOTES: Level I. Also checked on Home in DSH-001.

**TEST ID:** CUR-012 · **MODULE:** Currency · **TITLE:** Exchange-rate validation
- PRECONDITIONS: Settings → Exchange rate.
- STEPS: Enter 0; −280; empty; "abc"; 278.705; 280.
- EXPECTED RESULT: First four refused with a message; 278.705 and 280 accepted and stored exactly (Decimal).
- NOTES: Level U + UI.

## 5. M2 — Accounts (ACC) — full format

**TEST ID:** ACC-001 · **MODULE:** Accounts · **TITLE:** Create an account
- PRECONDITIONS: Real mode, no accounts.
- STEPS: Add "Test Bank", type Bank, PKR, opening Rs 10,000 on 1 Oct 2026, colour blue, include in totals on.
- EXPECTED RESULT: Account listed; balance Rs 10,000; available total Rs 10,000; UUID id, createdAt and updatedAt set.
- NOTES: Level UI + I.

**TEST ID:** ACC-002 · **MODULE:** Accounts · **TITLE:** Balance = opening + posted transactions
- PRECONDITIONS: ACC-001 account.
- STEPS: Post expense Rs 1,500, income Rs 5,000, transfer out Rs 2,000 to Cash.
- EXPECTED RESULT: Test Bank Rs 11,500; Cash +Rs 2,000; no editable balance field exists.
- NOTES: Level U + I. ACC-03.

**TEST ID:** ACC-003 · **MODULE:** Accounts · **TITLE:** Pending transactions excluded from balance
- PRECONDITIONS: ACC-002 state.
- STEPS: 1. Add expense Rs 3,000 status Pending. 2. Mark it Posted.
- EXPECTED RESULT: 1. Balance stays Rs 11,500, row marked "Pending". 2. Balance Rs 8,500.
- NOTES: Level I.

**TEST ID:** ACC-004 · **MODULE:** Accounts · **TITLE:** Balance adjustment is a visible transaction
- PRECONDITIONS: Test Bank Rs 11,500.
- STEPS: Reconcile → real balance Rs 11,000.
- EXPECTED RESULT: Adjustment −Rs 500 appears in the account history; balance Rs 11,000; not counted as spending or income.
- NOTES: Level I. ACC-04.

**TEST ID:** ACC-005 · **MODULE:** Accounts · **TITLE:** Account with transactions can be archived, not deleted
- PRECONDITIONS: Test Bank with transactions.
- STEPS: 1. Try Delete. 2. Archive. 3. Open the account picker and history.
- EXPECTED RESULT: 1. Only "Archive" offered, with explanation. 2. Archived. 3. Not in pickers; history and transactions kept; balance still counted only if include-in-totals is on.
- NOTES: Level UI + I. ACC-05.

**TEST ID:** ACC-006 · **MODULE:** Accounts · **TITLE:** Include-in-totals flag
- PRECONDITIONS: Sample accounts.
- STEPS: Turn off include-in-totals for Fasset.
- EXPECTED RESULT: Available Rs 458,200 (484,800 − 26,600); Fasset still shows its own $95.00 balance.
- NOTES: Level I.

**TEST ID:** ACC-007 · **MODULE:** Accounts · **TITLE:** Sample accounts balances
- PRECONDITIONS: Sample mode on.
- STEPS: Open Accounts.
- EXPECTED RESULT: 9 accounts: HBL Rs 182,400 · Meezan Rs 48,000 · Cash Rs 26,000 · Easypaisa Rs 21,350 · SadaPay Rs 12,450 · NayaPay Rs 9,800 · Wise $520.00 (≈ Rs 145,600) · Fasset $95.00 (≈ Rs 26,600) · RedotPay $45.00 (≈ Rs 12,600); total Rs 484,800.
- NOTES: Level I + UI. Balances must be computed from fixture transactions, not stored.

**TEST ID:** ACC-008 · **MODULE:** Accounts · **TITLE:** Account validation
- PRECONDITIONS: Add account form.
- STEPS: Empty name; name of an existing account; opening balance with 3 decimals; change currency of an account that has transactions.
- EXPECTED RESULT: Empty name refused; duplicate name warned; 3 decimals refused for PKR/USD; currency locked once transactions exist.
- NOTES: Level U + UI.

## 6. M2 — Transactions (TXN-001…015) — full format

**TEST ID:** TXN-001 · **MODULE:** Transactions · **TITLE:** Expense reduces account balance and adds spending
- PRECONDITIONS: Sample data without the 6 Oct Shell row; HBL Rs 196,917.
- STEPS: Add expense Rs 14,517, Transport › Fuel, payee "Shell, Gulberg", HBL, 6 Oct.
- EXPECTED RESULT: HBL Rs 182,400; Transport spending Rs 16,367; October spent Rs 78,374 (after M4 counting rules).
- NOTES: Level I.

**TEST ID:** TXN-002 · **MODULE:** Transactions · **TITLE:** Income increases balance
- PRECONDITIONS: Wise $270.00.
- STEPS: Add income $250.00, Income › Reimbursement, Wise, 5 Oct (no split in M2).
- EXPECTED RESULT: Wise $520.00; income +$250.00 (≈ Rs 70,000). After M5 split rule, my income is $125 (SPL-003).
- NOTES: Level I.

**TEST ID:** TXN-003 · **MODULE:** Transactions · **TITLE:** Same-currency transfer is not income or spending
- PRECONDITIONS: Sample data.
- STEPS: Transfer Rs 5,000 HBL → Cash.
- EXPECTED RESULT: HBL Rs 177,400; Cash Rs 31,000; available Rs 484,800 unchanged; October spent and income unchanged.
- NOTES: Level I. TXN-03.

**TEST ID:** TXN-004 · **MODULE:** Transactions · **TITLE:** Cross-currency transfer Wise → HBL
- PRECONDITIONS: Sample data without the 5 Oct transfer: Wise $1,020.00, HBL Rs 43,050.
- STEPS: Transfer sent $500.00 from Wise, received Rs 139,350 into HBL, 5 Oct.
- EXPECTED RESULT: Wise $520.00; HBL Rs 182,400; rate 278.70 shown and stored; available total drops by Rs 650 only (rate difference); spending and income unchanged.
- NOTES: Level I + UI. US-03.

**TEST ID:** TXN-005 · **MODULE:** Transactions · **TITLE:** Refund reduces category spending
- PRECONDITIONS: Sample data (Food Rs 15,470; SadaPay Rs 12,450).
- STEPS: Add Refund Rs 500, Food › Food delivery, payee Foodpanda, SadaPay.
- EXPECTED RESULT: SadaPay Rs 12,950; Food Rs 14,970; total income unchanged.
- NOTES: Level I. §18 refunds.

**TEST ID:** TXN-006 · **MODULE:** Transactions · **TITLE:** Edit account moves the balance effect
- PRECONDITIONS: Sample data.
- STEPS: Edit Jazz postpaid Rs 1,500 from HBL to Meezan.
- EXPECTED RESULT: HBL Rs 183,900; Meezan Rs 46,500; available unchanged.
- NOTES: Level I.

**TEST ID:** TXN-007 · **MODULE:** Transactions · **TITLE:** Edit date across a month boundary
- PRECONDITIONS: Sample data.
- STEPS: Edit Office rent date from 1 Oct to 30 Sep.
- EXPECTED RESULT: October spent Rs 48,374 (−30,000 my share, after M5); September +Rs 30,000; balances unchanged.
- NOTES: Level I. Re-run after M5 with split shares.

**TEST ID:** TXN-008 · **MODULE:** Transactions · **TITLE:** Delete is soft and restores balance
- PRECONDITIONS: Sample data; Test entry Rs 100 on 1 Oct (Cash) restored first.
- STEPS: Delete "Test entry".
- EXPECTED RESULT: deletedAt set; hidden from lists and totals; Cash balance back; row still in DB (restorable in M3).
- NOTES: Level I.

**TEST ID:** TXN-009 · **MODULE:** Transactions · **TITLE:** Invalid transaction input refused
- PRECONDITIONS: Add / Transfer sheets.
- STEPS: Amount 0; amount empty; 13 integer digits; no account; transfer with From = To; cross-currency transfer without received amount; received amount 0.
- EXPECTED RESULT: Each refused with its own message; Save disabled where applicable; nothing written to DB.
- NOTES: Level U + UI.

**TEST ID:** TXN-010 · **MODULE:** Transactions · **TITLE:** Quick add defaults
- PRECONDITIONS: Last transaction used SadaPay; recent categories Food delivery, Dining out.
- STEPS: Tap "+", enter 2,180, pick the first suggested category, Save.
- EXPECTED RESULT: Account preselected SadaPay; recent categories listed first; saved in ≤ 4 taps after the amount.
- NOTES: Level UI. TXN-06, OBJ-3.

**TEST ID:** TXN-011 · **MODULE:** Transactions · **TITLE:** Month bucketing uses the recorded time zone
- PRECONDITIONS: Device Asia/Karachi (UTC+5).
- STEPS: 1. Add expense 31 Oct 2026 23:30. 2. Change device zone to Asia/Dubai (UTC+4) and to UTC−5. 3. Check October totals.
- EXPECTED RESULT: Stored 2026-10-31T18:30Z with zone Asia/Karachi; it stays in October and shows 31 Oct 23:30 in all cases.
- NOTES: Level U + I. CAL-07.

**TEST ID:** TXN-012 · **MODULE:** Transactions · **TITLE:** Saves are atomic
- PRECONDITIONS: Fault injection: the second leg of a transfer insert throws.
- STEPS: Save transfer HBL → Cash Rs 5,000.
- EXPECTED RESULT: Error message shown; neither leg saved; balances unchanged.
- NOTES: Level I.

**TEST ID:** TXN-013 · **MODULE:** Transactions · **TITLE:** Undo after save
- PRECONDITIONS: Add sheet.
- STEPS: Save expense Rs 640 Careem, then tap Undo on the toast.
- EXPECTED RESULT: Transaction removed, balance back; nothing in Recently Deleted (undo ≠ delete).
- NOTES: Level UI. AUD-13.

**TEST ID:** TXN-014 · **MODULE:** Transactions · **TITLE:** Repeat this transaction
- PRECONDITIONS: Careem Rs 1,850 on 3 Oct (Easypaisa).
- STEPS: Open it → "Repeat this".
- EXPECTED RESULT: Add sheet prefilled with Rs 1,850, Transport › Ride-hailing, Easypaisa, today's date; nothing saved until confirm.
- NOTES: Level UI. TXN-07 (S).

**TEST ID:** TXN-015 · **MODULE:** Transactions · **TITLE:** Transfers and adjustments excluded from income/expense totals
- PRECONDITIONS: Sample data incl. Wise → HBL transfer and an adjustment −Rs 500.
- STEPS: Compute October income and expense totals.
- EXPECTED RESULT: Totals identical with and without the transfer and adjustment.
- NOTES: Level U + I.

## 7. M3 — Categories, Activity, attachments, Recently Deleted (compact)

| ID | Lvl | Title | Expected result | Status |
|---|---|---|---|---|
| CAT-001 | I | Default category tree | Expense and income trees equal PRD Appendix A; colours as UI-007 | Not run |
| CAT-002 | UI | Rename and reorder | New name/order shown everywhere, history keeps link (by id) | Not run |
| CAT-003 | UI | Hide category | Not in picker; old transactions still show it | Not run |
| CAT-004 | I | Merge categories | All transactions moved in one DB transaction; budget limits merged; no orphans | Not run |
| CAT-005 | UI | Delete category with transactions | Blocked; merge offered | Not run |
| CAT-006 | I | Tags | Several tags per transaction; filter by tag returns exact rows | Not run |
| CAT-007 | I | Payee remembers last category | New "Kababjees" entry suggests Food › Dining out | Not run |
| CAT-008 | U | Category suggestion from payee/note (AI-01) | "Careem" → Transport › Ride-hailing; unknown payee → no suggestion | Not run |
| TXN-020 | UI | Activity day totals (my share) | Tue 6 Oct Rs 16,117 · Mon 5 Rs 19,690 · Sun 4 Rs 6,200 · Sat 3 Rs 2,687 · Fri 2 Rs 3,680 · Thu 1 Rs 30,000 | Not run |
| TXN-021 | UI | Row says what the money did | Office rent: "You paid Rs 60,000 · your share Rs 30,000"; transfer and loan rows marked "not spending" | Not run |
| TXN-022 | I | Filter by account HBL (Oct) | 4 rows: Office rent, Jazz postpaid, Wise → HBL transfer, Shell | Not run |
| TXN-023 | I | Filter by category Food (Oct) | 3 rows totalling Rs 15,470 | Not run |
| TXN-024 | I | Filter by group / type / date range | Office group → 4 rows; Type Transfer → 1; 5–5 Oct → 5 rows | Not run |
| TXN-025 | I | Search payee, note, amount | "8940" → Imtiaz Super Market; "shell" → Shell, Gulberg; case-insensitive | Not run |
| TXN-026 | UI | Transaction detail and edit | Shows amount, account, category, split, tags, receipt; edits saved and reflected in list | Not run |
| TXN-027 | U | Split one transaction across categories (TXN-08) | Parts must sum to total before Save; each part counts in its category | Not run |
| TXN-028 | UI | Empty and no-result states | "No transactions yet" with Add; "No results for …" with Clear filters | Not run |
| ATT-001 | UI | Attach photo (camera / library) | Thumbnail on detail; opens full screen | Not run |
| ATT-002 | UI | Attach PDF from Files | PDF opens in viewer | Not run |
| ATT-003 | I | Attachment storage | Stored in protected app storage; survives relaunch; purged with its transaction | Not run |
| ATT-004 | M | Photos permission denied | Camera and Files still work; explanation shown | Not run |
| DATA-010 | I | Recently Deleted list | Sample: Careem Rs 640 · 2 Oct, Duplicate Imtiaz Rs 8,940 · 5 Oct, Test entry Rs 100 · 1 Oct | Not run |
| DATA-011 | I | Restore | Item back in lists; account balance and budgets include it again | Not run |
| DATA-012 | I | Purge after 30 days (clock + 31 days) | Item and attachments permanently removed | Not run |
| DATA-013 | I | Day 29 boundary | Item still restorable | Not run |
| DATA-014 | I | Transfer delete/restore | Both legs deleted and restored together | Not run |

---

## 8. M4 — Budgeting (BUD) — full format

All BUD tests use the sample dataset and October 2026 calendar-month budget unless stated.

**TEST ID:** BUD-001 · **MODULE:** Budget · **TITLE:** Create a monthly budget
- PRECONDITIONS: No budget for October.
- STEPS: Budget tab → Set budget → total Rs 235,000 → Save.
- EXPECTED RESULT: October budget saved; card shows total Rs 235,000, period "1–31 Oct".
- NOTES: Level UI + I. BUD-01.

**TEST ID:** BUD-002 · **MODULE:** Budget · **TITLE:** Category limits and unassigned amount
- PRECONDITIONS: BUD-001.
- STEPS: Set limits Office 75,000 · Transport 75,000 · Food 30,000 · Financial 20,000 · Subscriptions 15,000 · Utilities 12,000 · Personal 5,000.
- EXPECTED RESULT: Limits total Rs 232,000; "Rs 3,000 unassigned".
- NOTES: Level U + UI.

**TEST ID:** BUD-003 · **MODULE:** Budget · **TITLE:** October spent, left and percent
- PRECONDITIONS: BUD-002; October sample transactions.
- STEPS: Open Budget.
- EXPECTED RESULT: Spent Rs 78,374 · Left Rs 156,626 · 33% used.
- NOTES: Level U + I. Critical integration test (TEST_PLAN §6). Re-run in M5 as SPL-016.

**TEST ID:** BUD-004 · **MODULE:** Budget · **TITLE:** Category utilization and remaining
- PRECONDITIONS: BUD-003.
- STEPS: Read each category row.
- EXPECTED RESULT: Office 38,000/75,000 (51%, left 37,000) · Transport 16,367/75,000 (22%, left 58,633) · Food 15,470/30,000 (52%, left 14,530) · Financial 0/20,000 (0%) · Subscriptions 837/15,000 (6%) · Utilities 1,500/12,000 (13%) · Personal 6,200/5,000 (124%).
- NOTES: Level U. Utilisation computed in basis points, half-up (DATA_MODEL), shown as whole percent half-up (33.35% → 33%, 12.5% → 13%).

**TEST ID:** BUD-005 · **MODULE:** Budget · **TITLE:** Overspending shown in words
- PRECONDITIONS: BUD-003.
- STEPS: Read Personal row and Budget alerts.
- EXPECTED RESULT: "Over by Rs 1,200" (124%) with a symbol and word, not colour only; Home alert lists Personal over budget (M8).
- NOTES: Level U + UI.

**TEST ID:** BUD-006 · **MODULE:** Budget · **TITLE:** Warning threshold boundary (80%)
- PRECONDITIONS: Fresh month; Food limit Rs 30,000; threshold 80%.
- STEPS: 1. Add Food expenses totalling Rs 23,999. 2. Add Rs 1. 3. Add Rs 500.
- EXPECTED RESULT: 1. No warning. 2. Warning "Food 80% used" once. 3. No second warning. Same rule for US-04: Food 40,000 warns at Rs 32,000.
- NOTES: Level U. In-app here; notification in M7 (CAL-009).

**TEST ID:** BUD-007 · **MODULE:** Budget · **TITLE:** Exceeded alert
- PRECONDITIONS: Food limit Rs 30,000.
- STEPS: 1. Spend exactly Rs 30,000. 2. Add Rs 1.
- EXPECTED RESULT: 1. "Limit reached", no exceeded alert. 2. "Over by Rs 1" alert once.
- NOTES: Level U. Exceeded means spent > limit.

**TEST ID:** BUD-008 · **MODULE:** Budget · **TITLE:** Threshold is editable and validated
- PRECONDITIONS: Settings → Budget warning.
- STEPS: Set 90%; then 0%; then 101%; then empty.
- EXPECTED RESULT: 90% saved, Food warns at Rs 27,000; 0, 101 and empty refused with a message.
- NOTES: Level U + UI. SET-03.

**TEST ID:** BUD-009 · **MODULE:** Budget · **TITLE:** Editing a limit recalculates
- PRECONDITIONS: BUD-003.
- STEPS: Change Food limit to Rs 20,000.
- EXPECTED RESULT: Food left Rs 4,530 (77%); unassigned Rs 13,000; total unchanged.
- NOTES: Level U + I.

**TEST ID:** BUD-010 · **MODULE:** Budget · **TITLE:** Removing a category limit
- PRECONDITIONS: BUD-003.
- STEPS: Remove the Financial limit.
- EXPECTED RESULT: Unassigned Rs 23,000; Financial spending still counts in total spent.
- NOTES: Level U + I.

**TEST ID:** BUD-011 · **MODULE:** Budget · **TITLE:** Invalid budget values
- PRECONDITIONS: Budget limits editor.
- STEPS: Total 0; negative limit; text; add Health 10,000 making limits Rs 242,000 > total Rs 235,000.
- EXPECTED RESULT: Refused with messages; last case: "Category limits exceed total by Rs 7,000" and option to raise the total; nothing saved.
- NOTES: Level U + UI. Block vs warn to be confirmed in DESIGN_SYSTEM; test follows the approved behaviour.

**TEST ID:** BUD-012 · **MODULE:** Budget · **TITLE:** New month copies limits, no rollover
- PRECONDITIONS: October budget as BUD-002; clock moved to 1 Nov 2026 00:05 PKT.
- STEPS: Open Budget.
- EXPECTED RESULT: November budget exists with total Rs 235,000 and same limits; spent Rs 0; October's Rs 156,626 left is not carried over.
- NOTES: Level U + I. BUD-05.

**TEST ID:** BUD-013 · **MODULE:** Budget · **TITLE:** History is preserved
- PRECONDITIONS: BUD-012.
- STEPS: Change November Food to 35,000; open October from history.
- EXPECTED RESULT: October still Food 30,000, spent 78,374, left 156,626.
- NOTES: Level I. BUD-06.

**TEST ID:** BUD-014 · **MODULE:** Budget · **TITLE:** Six-month budget history
- PRECONDITIONS: Fixture Apr–Sep 2026.
- STEPS: Open budget history.
- EXPECTED RESULT: Spending Apr 198k · May 205k · Jun 226k · Jul 219k · Aug 248k · Sep 232k (Rs 231,565); "Budget kept 5 of 6 months (Aug over)".
- NOTES: Level I.

**TEST ID:** BUD-015 · **MODULE:** Budget · **TITLE:** Only my share counts
- PRECONDITIONS: Office rent Rs 60,000 (I paid, equal), electricity Rs 12,800 (partner paid, equal), tea Rs 3,200 (I paid, equal).
- STEPS: Read Office category.
- EXPECTED RESULT: Office spent Rs 38,000 (30,000 + 6,400 + 1,600), not Rs 76,000.
- NOTES: Level U (M4 with fixture shares) + I (M5 real splits). BUD-07, SPL-05.

**TEST ID:** BUD-016 · **MODULE:** Budget · **TITLE:** Exclusions and refunds
- PRECONDITIONS: BUD-003.
- STEPS: 1. Add transfer HBL → Cash Rs 5,000. 2. Lend Rs 20,000 (exists). 3. Settle up Rs 9,800 (M5). 4. Refund Rs 500 to Food.
- EXPECTED RESULT: Steps 1–3: spent stays Rs 78,374. Step 4: spent Rs 77,874; Food Rs 14,970.
- NOTES: Level U + I.

**TEST ID:** BUD-017 · **MODULE:** Budget · **TITLE:** USD expenses at current table rate
- PRECONDITIONS: iCloud+ $2.99.
- STEPS: 1. Read Subscriptions spent. 2. Change rate to 285.
- EXPECTED RESULT: 1. Rs 837. 2. Rs 852 (852.15); total spent Rs 78,389; note "USD at $1 = Rs 285".
- NOTES: Level U + I. CUR-04.

**TEST ID:** BUD-018 · **MODULE:** Budget · **TITLE:** Salary-cycle period boundaries
- PRECONDITIONS: Settings → Budget period: salary cycle, start day 21; zone Asia/Karachi.
- STEPS: 1. Read the period for 6 Oct. 2. Add expense 20 Oct 23:59. 3. Add expense 21 Oct 00:00.
- EXPECTED RESULT: 1. "21 Sep – 20 Oct". 2. In that period. 3. In "21 Oct – 20 Nov".
- NOTES: Level U. BUD-01.

**TEST ID:** BUD-019 · **MODULE:** Budget · **TITLE:** Salary cycle in short months and leap years
- PRECONDITIONS: Salary cycle start day 31.
- STEPS: Generate periods Jan 2027 → Dec 2028.
- EXPECTED RESULT: Starts clamp to month length (31 Jan 2027, 28 Feb 2027, 31 Mar 2027 … 29 Feb 2028); every day belongs to exactly one period; none skipped.
- NOTES: Level U.

**TEST ID:** BUD-020 · **MODULE:** Budget · **TITLE:** Switching calendar month ↔ salary cycle
- PRECONDITIONS: October calendar budget active on 6 Oct.
- STEPS: Switch to salary cycle (start 21).
- EXPECTED RESULT: Preview shows October ending 20 Oct as a shortened period and the first cycle 21 Oct – 20 Nov; no transaction counted in two periods or in none; limits copied.
- NOTES: Level U + UI. Transition rule to confirm with the owner before M4 starts.

**TEST ID:** BUD-021 · **MODULE:** Budget · **TITLE:** Group budget (Office)
- PRECONDITIONS: Office group budget Rs 150,000.
- STEPS: Open Office group budget.
- EXPECTED RESULT: Whole-group spend Rs 76,000 of Rs 150,000 (51%); personal budget still counts only my share.
- NOTES: Level U + I. BUD-07 (S).

**TEST ID:** BUD-022 · **MODULE:** Budget · **TITLE:** Empty state and persistence
- PRECONDITIONS: 1. No budget. 2. Then BUD-002 done.
- STEPS: 1. Open Budget. 2. Relaunch app.
- EXPECTED RESULT: 1. "Set a budget" card, no percentages, no crash. 2. Budget and limits unchanged after relaunch.
- NOTES: Level UI.

---

## 9. M5 — Loans (LOAN-001…012) — full format

**TEST ID:** LOAN-001 · **MODULE:** Loans · **TITLE:** Lending creates the account transaction and the loan together
- PRECONDITIONS: Easypaisa Rs 41,350; Usama exists.
- STEPS: People → Usama → Lend Rs 20,000 from Easypaisa, 6 Oct → confirm.
- EXPECTED RESULT: Easypaisa Rs 21,350; loan "owed to me" Rs 20,000, Open; not spending, not income; both rows saved in one DB transaction.
- NOTES: Level I + UI. LOAN-05.

**TEST ID:** LOAN-002 · **MODULE:** Loans · **TITLE:** Partial repayment
- PRECONDITIONS: Lent Usama Rs 10,000 on 2 Sep (Cash).
- STEPS: Record repayment Rs 5,000 on 20 Sep into Easypaisa.
- EXPECTED RESULT: Remaining Rs 5,000; status Partially paid; Easypaisa +Rs 5,000; not income.
- NOTES: Level U + I. LOAN-03.

**TEST ID:** LOAN-003 · **MODULE:** Loans · **TITLE:** Person net position
- PRECONDITIONS: LOAN-001 + LOAN-002.
- STEPS: Open Usama.
- EXPECTED RESULT: "Usama owes you Rs 25,000" (loans 25,000 + shared 0); follow-up 31 Oct shown.
- NOTES: Level U + I. US-05 variant, LOAN-04.

**TEST ID:** LOAN-004 · **MODULE:** Loans · **TITLE:** Borrowing
- PRECONDITIONS: HBL Rs 107,400 before.
- STEPS: Borrow Rs 75,000 from Ammi into HBL on 1 Aug, no due date.
- EXPECTED RESULT: HBL +Rs 75,000; "You owe Ammi Rs 75,000"; not income; no due date accepted.
- NOTES: Level I.

**TEST ID:** LOAN-005 · **MODULE:** Loans · **TITLE:** Full repayment settles
- PRECONDITIONS: Bilal owes Rs 10,000 (lent 15 Sep from HBL).
- STEPS: Record repayment Rs 10,000 into HBL.
- EXPECTED RESULT: Status Settled; Bilal balance Rs 0 "settled"; owed-to-you total drops by Rs 10,000.
- NOTES: Level U + I.

**TEST ID:** LOAN-006 · **MODULE:** Loans · **TITLE:** Overpayment refused
- PRECONDITIONS: Bilal owes Rs 10,000.
- STEPS: Record repayment Rs 12,000.
- EXPECTED RESULT: Refused: "More than the Rs 10,000 remaining"; nothing saved.
- NOTES: Level U + UI.

**TEST ID:** LOAN-007 · **MODULE:** Loans · **TITLE:** Loan totals
- PRECONDITIONS: Sample loans only (Usama, Bilal, Ammi).
- STEPS: Read loan totals.
- EXPECTED RESULT: Owed to you Rs 35,000; you owe (loans) Rs 75,000. With shared balances (M5) overall you owe Rs 88,000 (SPL-013).
- NOTES: Level U.

**TEST ID:** LOAN-008 · **MODULE:** Loans · **TITLE:** Simple interest
- PRECONDITIONS: Borrowed Rs 100,000 on 1 Jan 2027 at 12% per year simple.
- STEPS: Read balance on 1 Jul 2027 (181 days).
- EXPECTED RESULT: Interest Rs 5,950.68 (100,000 × 0.12 × 181/365, half-up); remaining Rs 105,950.68.
- NOTES: Level U. Day-count rule actual/365 to confirm in ARCHITECTURE.

**TEST ID:** LOAN-009 · **MODULE:** Loans · **TITLE:** Write off
- PRECONDITIONS: Bilal owes Rs 10,000.
- STEPS: Write off.
- EXPECTED RESULT: Status Written off; excluded from owed total; history kept; no account movement.
- NOTES: Level U + I.

**TEST ID:** LOAN-010 · **MODULE:** Loans · **TITLE:** Deleting a repayment
- PRECONDITIONS: LOAN-003 state.
- STEPS: Delete Usama's Rs 5,000 repayment.
- EXPECTED RESULT: Usama owes you Rs 30,000; Easypaisa −Rs 5,000; repayment in Recently Deleted; restoring returns to Rs 25,000.
- NOTES: Level I.

**TEST ID:** LOAN-011 · **MODULE:** Loans · **TITLE:** Fast entry of existing balances
- PRECONDITIONS: Real mode.
- STEPS: Add 3 opening balances without history (e.g. A owes me 5,000; I owe B 2,000; C owes me 1,000).
- EXPECTED RESULT: Balances appear; no account balance changes; totals owed Rs 6,000, owe Rs 2,000.
- NOTES: Level UI + I. LOAN-08.

**TEST ID:** LOAN-012 · **MODULE:** Loans · **TITLE:** Invalid loan input
- PRECONDITIONS: Lend sheet.
- STEPS: Amount 0; no person; due date before loan date; repay a USD loan from a PKR account without received amount.
- EXPECTED RESULT: Each refused with a clear message; nothing saved.
- NOTES: Level U + UI.

## 10. M5 — Splitting and groups (SPL) — full format

**TEST ID:** SPL-001 · **MODULE:** Split · **TITLE:** Equal split, I paid
- PRECONDITIONS: Office group (me + Office partner, equally).
- STEPS: Add Office rent Rs 60,000, HBL, 1 Oct, split with Office, paid by me.
- EXPECTED RESULT: HBL −Rs 60,000; my spending Rs 30,000; partner owes me Rs 30,000 for this item.
- NOTES: Level U + I.

**TEST ID:** SPL-002 · **MODULE:** Split · **TITLE:** Expense paid by someone else
- PRECONDITIONS: Office group.
- STEPS: Add Office electricity Rs 12,800, 5 Oct, paid by Office partner, equally.
- EXPECTED RESULT: No account changes; my spending Rs 6,400; I owe partner Rs 6,400 for this item.
- NOTES: Level U + I. SPL-06.

**TEST ID:** SPL-003 · **MODULE:** Split · **TITLE:** Shared income
- PRECONDITIONS: Office group.
- STEPS: Add income $250.00 Office reimbursement into Wise, 5 Oct, split equally.
- EXPECTED RESULT: Wise +$250.00; my income $125.00 (≈ Rs 35,000); I owe partner $125.00 (≈ Rs 35,000).
- NOTES: Level U + I. SPL-10.

**TEST ID:** SPL-004 · **MODULE:** Split · **TITLE:** Office group balance
- PRECONDITIONS: SPL-001, SPL-002, SPL-003 + tea & snacks Rs 3,200 from Cash, I paid, equally.
- STEPS: Open Office group.
- EXPECTED RESULT: +30,000 − 6,400 − 35,000 + 1,600 → "You owe Office partner Rs 9,800"; footnote USD at $1 = Rs 280.
- NOTES: Level U + I. Critical integration test. US-08.

**TEST ID:** SPL-005 · **MODULE:** Split · **TITLE:** Exact amounts must match the total
- PRECONDITIONS: Expense Rs 3,200 with Office.
- STEPS: 1. Exact: me 2,000, partner 1,000. 2. Change partner to 1,200.
- EXPECTED RESULT: 1. Save disabled, "Rs 200 left to assign". 2. Saved; my spending Rs 2,000.
- NOTES: Level U + UI. SPL-04.

**TEST ID:** SPL-006 · **MODULE:** Split · **TITLE:** Percentages
- PRECONDITIONS: Expense Rs 10,000 with Office.
- STEPS: 1. 55% / 40%. 2. 60% / 40%.
- EXPECTED RESULT: 1. Save disabled, "95% of 100%". 2. Shares Rs 6,000 / Rs 4,000.
- NOTES: Level U.

**TEST ID:** SPL-007 · **MODULE:** Split · **TITLE:** Shares
- PRECONDITIONS: none.
- STEPS: 1. Rs 3,000 at 2:1. 2. Rs 1,000 at 1:1:1.
- EXPECTED RESULT: 1. Rs 2,000 / Rs 1,000. 2. Rs 333.34 / Rs 333.33 / Rs 333.33 (sum Rs 1,000.00).
- NOTES: Level U.

**TEST ID:** SPL-008 · **MODULE:** Split · **TITLE:** Equal split remainders never lose a paisa
- PRECONDITIONS: none.
- STEPS: 1. Rs 100.00 among 3. 2. Rs 0.01 among 2. 3. Property test: 10,000 random totals and member counts 2–10.
- EXPECTED RESULT: 1. 33.34 + 33.33 + 33.33. 2. 0.01 + 0.00. 3. Shares always sum to the total; remainder minor units go one each in member order starting with the first payer (DATA_MODEL), same result every run.
- NOTES: Level U. §18 precision.

**TEST ID:** SPL-009 · **MODULE:** Split · **TITLE:** Equal among selected members only
- PRECONDITIONS: Hunza trip group (me, Ali, Sara, Bilal).
- STEPS: Dinner Rs 4,000 paid by me, equally among me, Ali, Sara.
- EXPECTED RESULT: Shares 1,333.34 / 1,333.33 / 1,333.33; Ali and Sara each owe me Rs 1,333.33; Bilal unaffected.
- NOTES: Level U.

**TEST ID:** SPL-010 · **MODULE:** Split · **TITLE:** Several payers
- PRECONDITIONS: Hunza trip group.
- STEPS: Hotel Rs 9,000 paid by me Rs 5,000 + Ali Rs 4,000; split equally among me, Ali, Sara.
- EXPECTED RESULT: Each share Rs 3,000; I am owed Rs 2,000, Ali is owed Rs 1,000, Sara owes Rs 3,000; my spending Rs 3,000; my account −Rs 5,000.
- NOTES: Level U + I. Payer amounts must sum to Rs 9,000 before Save.

**TEST ID:** SPL-011 · **MODULE:** Split · **TITLE:** Settle up in full
- PRECONDITIONS: SPL-004 (you owe Rs 9,800).
- STEPS: Office → Settle up → Rs 9,800 from HBL → confirm.
- EXPECTED RESULT: "Settled up"; HBL −Rs 9,800; not spending; settlement listed in group activity.
- NOTES: Level I + UI. SPL-08.

**TEST ID:** SPL-012 · **MODULE:** Split · **TITLE:** Partial settle up
- PRECONDITIONS: SPL-004.
- STEPS: Settle Rs 5,000 from Cash.
- EXPECTED RESULT: "You owe Office partner Rs 4,800"; Cash −Rs 5,000.
- NOTES: Level U + I.

**TEST ID:** SPL-013 · **MODULE:** People · **TITLE:** Overall owed / owe
- PRECONDITIONS: Full sample (loans + groups).
- STEPS: Open People.
- EXPECTED RESULT: "Owed to you Rs 35,000 · You owe Rs 88,000"; Usama owes you 25,000 · Bilal owes you 10,000 · Sara settled · Ali you owe 3,200 · Office partner you owe 9,800 · Ammi you owe 75,000.
- NOTES: Level U + I. Critical integration test. SPL-07, DSH-03.

**TEST ID:** SPL-014 · **MODULE:** Split · **TITLE:** Simplify debts
- PRECONDITIONS: Group with Bilal owes me Rs 2,000 and I owe Ali Rs 2,000; second case 5 members with random balances (property test).
- STEPS: Simplify.
- EXPECTED RESULT: Case 1: one payment, Bilal pays Ali Rs 2,000. Property: every member's net unchanged; payments ≤ members − 1.
- NOTES: Level U. SPL-09 (S).

**TEST ID:** SPL-015 · **MODULE:** Split · **TITLE:** Editing a split recomputes balances and budget
- PRECONDITIONS: SPL-004.
- STEPS: Change Office rent to percentages me 60% / partner 40%.
- EXPECTED RESULT: My share Rs 36,000; partner owes Rs 24,000 for rent; Office: you owe Rs 15,800; October spent Rs 84,374.
- NOTES: Level U + I.

**TEST ID:** SPL-016 · **MODULE:** Budget · **TITLE:** Budget with real split data
- PRECONDITIONS: Full sample entered through the M5 split engine.
- STEPS: Open Budget.
- EXPECTED RESULT: Spent Rs 78,374 · Left Rs 156,626 · Office Rs 38,000 (same as BUD-003).
- NOTES: Level I. Re-run of BUD-003 on real splits.

**TEST ID:** SPL-017 · **MODULE:** Split · **TITLE:** Deleting a split expense
- PRECONDITIONS: SPL-004.
- STEPS: Delete tea & snacks Rs 3,200.
- EXPECTED RESULT: Office: you owe Rs 11,400; Cash +Rs 3,200; October spent Rs 76,774; restore returns to Rs 9,800.
- NOTES: Level I.

**TEST ID:** SPL-018 · **MODULE:** Groups · **TITLE:** Removing a member with a balance
- PRECONDITIONS: SPL-004.
- STEPS: 1. Remove Office partner. 2. After SPL-011, remove again.
- EXPECTED RESULT: 1. Blocked: "Settle Rs 9,800 first". 2. Allowed; history kept.
- NOTES: Level U + UI.

**TEST ID:** SPL-019 · **MODULE:** Groups · **TITLE:** Group activity and monthly totals
- PRECONDITIONS: SPL-004.
- STEPS: Open Office → activity, October totals.
- EXPECTED RESULT: 4 items newest first; whole-group spend Rs 76,000; my share Rs 38,000.
- NOTES: Level I + UI. SPL-12 (S).

**TEST ID:** SPL-020 · **MODULE:** Groups · **TITLE:** Mixed-currency group balance at current rate
- PRECONDITIONS: SPL-004.
- STEPS: Change rate to 285.
- EXPECTED RESULT: Partner's half shows "$125.00 ≈ Rs 35,625"; Office: you owe Rs 10,425 (30,000 − 6,400 − 35,625 + 1,600), footnote "USD at $1 = Rs 285"; back to 280 → Rs 9,800.
- NOTES: Level U. Each share stored in its own currency.

---

## 11. M6 — Recurring, subscriptions, kameti, installments (compact)

| ID | Lvl | Title | Expected result | Status |
|---|---|---|---|---|
| REC-001 | U | Monthly item next due | Internet Rs 6,500 on the 8th → next due Thu 8 Oct | Not run |
| REC-002 | I | Mark paid posts and advances | Netflix: expense Rs 1,100, Subscriptions › Streaming, HBL; next due 12 Nov | Not run |
| REC-003 | I | Mark paid with edited amount | Gas estimate Rs 3,250 → paid Rs 3,410; Utilities +3,410; estimate unchanged | Not run |
| REC-004 | I | Skip | No transaction; next due advances one period | Not run |
| REC-005 | U | Snooze 1 day | Internet due 9 Oct; snoozed status shown | Not run |
| REC-006 | U | Monthly on the 31st | 31 Oct → 30 Nov → 31 Dec → 31 Jan → 28 Feb 2027; 29 Feb 2028 | Not run |
| REC-007 | U | Weekly, quarterly, yearly, custom N days/months | Correct next dates for each, incl. every 45 days and every 2 months | Not run |
| REC-008 | U | End date | No occurrences after end date | Not run |
| REC-009 | U | Overdue | Gas due 5 Oct shows Overdue on 6 Oct | Not run |
| REC-010 | I | Recurring with split | Office staff salaries Rs 70,000 → my share Rs 35,000 posted as split when paid | Not run |
| REC-011 | I | Recurring salary income | $1,875.00 to Wise on the 21st; mark received → income $1,875 | Not run |
| REC-012 | UI | Hub sections and totals | Bills, Subscriptions, Plans (kameti, car installment), Income, Paused/Cancelled; monthly and yearly totals | Not run |
| REC-013 | I | Deleting one recurring item | Other items and past transactions untouched (master prompt REG-017 example) | Not run |
| REC-014 | I | Mark paid is idempotent | Double tap / repeated action → exactly one transaction (unique occurrence id) | Not run |
| REC-015 | I | Editing amount affects future only | Netflix → Rs 1,200 from next due; past rows keep Rs 1,100; price history entry added | Not run |
| SUB-001 | U | Subscription totals | 6 active: Rs 14,065 / month; Rs 168,780 / year | Not run |
| SUB-002 | I | Price history | Netflix Rs 950 until Mar 2026, Rs 1,100 from Apr 2026; since Jan 2025 | Not run |
| SUB-003 | I | Cancel | Amazon Prime Video (Aug) listed Cancelled, excluded from totals | Not run |
| SUB-004 | I | Pause / resume | Paused excluded from totals and reminders; resume restores next due | Not run |
| SUB-005 | U | USD subscriptions | ChatGPT Plus $20.00 ≈ Rs 5,600; rate 285 → ≈ Rs 5,700 | Not run |
| SUB-006 | U | Yearly renewal date | Yearly sub renewed 15 Mar → next 15 Mar next year; 29 Feb → 28 Feb in non-leap year | Not run |
| KAM-001 | U | Kameti progress | 4 of 12 paid; Rs 80,000 of Rs 240,000; #5 due 15 Oct | Not run |
| KAM-002 | I | Record contribution #5 | Expense Financial › Kameti contribution Rs 20,000; 5 of 12; Rs 100,000; Financial spent Rs 20,000 | Not run |
| KAM-003 | I | Record payout | Dec 2026 payout Rs 150,000 → income Kameti payout; received Rs 150,000 of Rs 300,000 | Not run |
| KAM-004 | U | Figures mismatch note | Payouts Rs 300,000 ≠ contributions Rs 240,000 → "Check figures with the committee" | Not run |
| KAM-005 | U | Schedule | 12 contributions on the 15th, Jun 2026 → May 2027 | Not run |
| KAM-006 | U | Invalid kameti | Duration 0, contribution 0, payout date outside range → refused | Not run |
| LOAN-020 | U | Car installment schedule | Meezan Rs 45,000 × 36; 14 paid; #15 due 10 Oct; remaining Rs 990,000 (22 left); ends Jul 2028 | Not run |
| LOAN-021 | I | Pay installment #15 | Expense Transport › Car installment Rs 45,000 from Meezan; 15 of 36; remaining Rs 945,000 | Not run |
| LOAN-022 | U | Installment counts in budget | Paid installment adds Rs 45,000 to Transport spent | Not run |
| LOAN-023 | U | Late installment | Unpaid after 10 Oct → Overdue; schedule dates unchanged | Not run |

## 12. M7 — Calendar and reminders (compact)

Default reminder: 1 day before at 10:00 local (AS-05). Zone Asia/Karachi unless stated.

| ID | Lvl | Title | Expected result | Status |
|---|---|---|---|---|
| CAL-001 | U | October 2026 grid | Starts Thursday; 31 days; 6 Oct marked today | Not run |
| CAL-002 | UI | Dots per item | All 18 dataset items on the right days with type badges | Not run |
| CAL-003 | UI | Day list statuses | 5 Oct: Gas "! Overdue", Office electricity "✓ Paid"; 8 Oct: Internet "Due" | Not run |
| CAL-004 | U | Reminder creation (default) | Netflix due 12 Oct → reminder 11 Oct 10:00 | Not run |
| CAL-005 | U | Per-item override | Car installment same day 09:00 → 10 Oct 09:00 | Not run |
| CAL-006 | I | Modify item date | Old pending request removed, new one scheduled | Not run |
| CAL-007 | I | Delete item | Pending notification and calendar entry removed | Not run |
| CAL-008 | U | Repeating custom reminder (incl. non-money) | "Call bank" weekly Mon 09:00 → next occurrences planned | Not run |
| CAL-009 | I | Budget threshold notification | Food crosses 80% → one notification | Not run |
| CAL-010 | I | Monthly bill after paid | Internet paid 8 Oct → next reminder 7 Nov 10:00 | Not run |
| CAL-011 | U | Subscription renewal | Yearly subscription reminder 1 day before renewal | Not run |
| CAL-012 | U | Loan due and follow-up | Bilal due 31 Oct, Usama follow-up 31 Oct → reminders 30 Oct 10:00 | Not run |
| CAL-013 | U | Settle-up reminder (SPL-11) | Office month-end → reminder 30 Oct 10:00 | Not run |
| CAL-014 | U | Overdue, no nagging | Gas overdue: highlighted in app and Home alert; no repeated notification | Not run |
| CAL-015 | M | Notification permission first use | Prompt only when first reminder is set; granted → scheduled | Not run |
| CAL-016 | M | Notification permission denied | In-app calendar works; banner with Settings link; no crash | Not run |
| CAL-017 | M | Calendar permission denied | Export toggle off with explanation; in-app calendar unaffected | Not run |
| CAL-018 | M | EventKit export | Events created in chosen calendar; edit/delete in UZee updates/removes them; user's own events untouched | Not run |
| CAL-019 | U+M | Device clock changed | +3 days → Internet overdue, reminders re-planned on foreground; back → restored | Not run |
| CAL-020 | U+M | Time zone change | Karachi → Dubai: due dates keep calendar date; reminders 10:00 Dubai time | Not run |
| CAL-021 | U | DST zone | Europe/London reminder across 28 Mar 2027 stays 10:00 local | Not run |
| CAL-022 | U | Month boundary | Item on 31 Oct → next 30 Nov; reminder for 1 Nov fires 31 Oct | Not run |
| CAL-023 | U | Year boundary | Monthly item 31 Dec 2026 → 31 Jan 2027; navigation Dec 2026 → Jan 2027 | Not run |
| CAL-024 | U | Leap years | Feb 2028 grid has 29 days; yearly 29 Feb 2028 → 28 Feb 2029 | Not run |
| CAL-025 | U+I | 64 pending cap | 100 future occurrences → exactly 64 nearest planned; refreshed after mark paid and on launch | Not run |
| CAL-026 | M | Notification actions and privacy | Mark paid posts one transaction; Snooze 1 day re-notifies +24 h; Open deep-links; "hide amounts" removes amounts from text | Not run |

## 13. M8 — Dashboard and reports (compact)

| ID | Lvl | Title | Expected result | Status |
|---|---|---|---|---|
| DSH-001 | I+UI | Available balance | Rs 484,800 with "USD at $1 = Rs 280" | Not run |
| DSH-002 | I+UI | Budget left | Rs 156,626 of Rs 235,000 | Not run |
| DSH-003 | I+UI | Spent this month | Rs 78,374; "Rs 9,800 less than September" (1–6 Sep Rs 88,174) | Not run |
| DSH-004 | I+UI | Upcoming 7 days | Internet 8 Oct, Car installment 10 Oct, Netflix 12 Oct | Not run |
| DSH-005 | UI | Alert strip | Gas bill overdue; Personal over budget by Rs 1,200 | Not run |
| DSH-006 | I | Owed / owe | Owed to you Rs 35,000 · You owe Rs 88,000 | Not run |
| DSH-007 | U+I | Until next salary | 21 Oct, 15 days; due Rs 87,050 (83,800 + overdue 3,250); left after bills Rs 397,750 | Not run |
| DSH-008 | U | Forecast after paying | Mark Internet paid from HBL → due Rs 80,550, available Rs 478,300, left after bills still Rs 397,750 | Not run |
| DSH-009 | U+UI | Category donut | Office 48% · Transport 21% · Food 20% · Personal 8% · Utilities 2% · Subscriptions 1% | Not run |
| DSH-010 | UI | Shared card | Office: you owe Rs 9,800; Hunza trip: you owe Ali Rs 3,200 | Not run |
| DSH-011 | UI | Empty dashboard | New user: zero cards with "Add account" and "Set budget" actions, no errors | Not run |
| RPT-001 | I | September summary | Income Rs 560,000 · Spending Rs 231,565 · Net +Rs 328,435 | Not run |
| RPT-002 | I | September by category | Office 71,000 · Transport 67,000 · Food 34,000 · Financial 20,000 · Subscriptions 14,065 · Utilities 11,200 · Personal 9,800 · Health 4,500 | Not run |
| RPT-003 | I | Income vs spending, 6 months | Apr 560/198 · May 560/205 · Jun 560/226 · Jul 560/219 · Aug 595/248 · Sep 560/232 (Rs thousands) | Not run |
| RPT-004 | I | Budget performance | Kept 5 of 6 months; August over | Not run |
| RPT-005 | I | Subscriptions and recurring cost | Rs 14,065 / month, Rs 168,780 / year; bills Internet 6,500, Gas ~3,250, Mobile 1,500 | Not run |
| RPT-006 | I | Owed / owing per person | Same six balances as SPL-013 | Not run |
| RPT-007 | I | Office group report, October | Rent +30,000, electricity −6,400, reimbursement −35,000, tea +1,600 → you owe Rs 9,800 | Not run |
| RPT-008 | I | Account balances over time (S) | Month-end balances recompute to current Rs 484,800 | Not run |
| RPT-009 | I | Cash-flow trend (S) | 6–12 months net = income − spending per month | Not run |
| RPT-010 | U | Yearly / range totals | Apr–Sep: sum of monthly fixture values exactly (no rounding drift) | Not run |
| RPT-011 | I+M | PDF export | PDF opens in Files; totals and footnote equal the screen | Not run |
| RPT-012 | I | CSV export | UTF-8, header row, RFC 4180 quoting, amounts as decimal strings + currency column; row count = transactions | Not run |
| RPT-013 | U | Report rules | Shares only; transfers and loans excluded; footnote "Your shares only · transfers excluded · USD at $1 = Rs 280" | Not run |

## 14. M9 — Voice and Siri (compact)

| ID | Lvl | Title | Expected result | Status |
|---|---|---|---|---|
| VOX-001 | M | Siri: "ask UZee how much do I owe Ammi" | "You owe Ammi Rs 75,000" (same as People) | Not run |
| VOX-002 | U+M | Relationship alias | "my mother" → Ammi when tagged mother; otherwise asks "Who is your mother?" | Not run |
| VOX-003 | U | Next recurring payment | "Internet, Rs 6,500, Thursday 8 October" (plus "Gas bill is overdue") | Not run |
| VOX-004 | U | Subscriptions this month | Rs 14,065 | Not run |
| VOX-005 | U | Budget left | Rs 156,626 | Not run |
| VOX-006 | U | Category spending | "food this month" → Rs 15,470 | Not run |
| VOX-007 | M | Lend flow (PRD example) | "I sent 20k PKR to a friend…" → asks name → "Usama" → card "Lent Rs 20,000 to Usama from Easypaisa" → Save → LOAN-001 result | Not run |
| VOX-008 | U+M | Unknown person | "Hamza" not found → offers to create person; nothing saved until confirmed | Not run |
| VOX-009 | U | Cancel on card | No records created | Not run |
| VOX-010 | UI | Edit card fields | Change account on card → saved with edited account | Not run |
| VOX-011 | U | Amount phrases | "20k" → Rs 20,000; "1.5 lakh" → Rs 150,000; "$20" → $20.00; "two thousand five hundred" → Rs 2,500 | Not run |
| VOX-012 | U+M | Reminder/event by voice | "Remind me to collect from Bilal on 31 October" → reminder card → saved | Not run |
| VOX-013 | M | Model unavailable | Apple Intelligence off → explanation shown; fixed Siri commands still answer VOX-003…006 | Not run |
| VOX-014 | M | Evaluation suite | 50 fixed utterances; pass rate reported (target ≥ 90%) | Not run |
| VOX-015 | M | Latency and entry points | Answer starts ≤ 3 s; Action Button, Control Center and in-app mic open Voice | Not run |

## 15. M10 — Security, data, import, onboarding (compact)

| ID | Lvl | Title | Expected result | Status |
|---|---|---|---|---|
| SEC-001 | M | Face ID lock | Lock on → after timeout app requires Face ID | Not run |
| SEC-002 | M | Passcode fallback | Face ID fails/cancelled → device passcode unlocks | Not run |
| SEC-003 | M | App switcher privacy | Lock on → switcher shows cover, no amounts | Not run |
| SEC-004 | I | Logs clean | Full test run's logs contain no amounts, names or notes | Not run |
| SEC-005 | I | No network | No URLSession/Network usage in binary; proxy shows zero requests during full UI run | Not run |
| SEC-006 | I | Backup password never stored | Not in DB, UserDefaults, Keychain or logs | Not run |
| SEC-007 | M | Notification amount hiding | Option on → lock-screen text has no amounts | Not run |
| SEC-008 | M | Data Protection on all files | DB, WAL, attachments, temporary backup files protected | Not run |
| DATA-020 | I | Backup → restore round trip | All record counts, balances and attachment hashes equal | Not run |
| DATA-021 | I+UI | Restore summary and safety copy | Summary (counts, date) before replace; safety copy created | Not run |
| DATA-022 | I | Wrong password | Refused; current data untouched | Not run |
| DATA-023 | I | Tampered / truncated file | AES-GCM authentication fails; clear message; data untouched | Not run |
| DATA-024 | I | Migration from every earlier schema | v1…current fixtures migrate; safety copy made; totals unchanged | Not run |
| DATA-025 | I | Interrupted restore | Kill mid-restore → previous data intact on relaunch | Not run |
| DATA-026 | M | Large backup | 10k transactions + 50 attachments: backup and restore complete; time recorded | Not run |
| IMP-001 | I | Parse HBL statement PDF | Rows with date, description, amount, direction match the sample | Not run |
| IMP-002 | UI | Review screen | Rows editable, category suggested, rows excludable | Not run |
| IMP-003 | I | Nothing saved before confirm | Cancel → zero new rows | Not run |
| IMP-004 | I | Duplicate detection | Same account + date + amount flagged; default excluded | Not run |
| IMP-005 | I | Re-import same file | All rows flagged duplicate | Not run |
| IMP-006 | UI | Unsupported PDF | Clear "This bank's format isn't supported yet" message | Not run |
| IMP-007 | UI | Password-protected PDF | Asks for the PDF password; wrong password handled | Not run |
| IMP-008 | I | Reader per supplied bank sample | One sub-test per bank (IMP-008a HBL, b Meezan, …) added when samples arrive | Not run |
| IMP-009 | I | CSV import (S) | Mapped columns; same review and duplicate rules | Not run |
| UI-030 | UI | Onboarding complete | Base currency, salary day, accounts, Face ID choice saved | Not run |
| UI-031 | UI | Onboarding skip / sample data | Skip lands on empty Home; sample option follows DATA-001…004 | Not run |
| UI-032 | UI | Suggested accounts (ACC-06) | Easypaisa, NayaPay, SadaPay, HBL, Meezan, Wise (USD), Fasset (USD), RedotPay (USD), Cash (PKR) | Not run |
| UI-033 | UI | Import recommendation (IMP-05) | Onboarding recommends importing past statements | Not run |
| UI-034 | M | Receipt reading (AI-02) | Photo of receipt fills amount, date, merchant for review | Not run |

## 16. M11 — iPad, dark mode, accessibility, performance (compact)

| ID | Lvl | Title | Expected result | Status |
|---|---|---|---|---|
| UI-040 | UI | iPad portrait | Sidebar + content readable; no clipped amounts | Not run |
| UI-041 | UI | iPad landscape | Three-column where designed; selection kept | Not run |
| UI-042 | UI | Split View ⅓ width | Compact layout like iPhone | Not run |
| UI-043 | M | Stage Manager resize | Layout adapts live, no crash | Not run |
| UI-044 | UI | Keyboard shortcuts | ⌘N add, ⌘F search | Not run |
| UI-045 | UI | Dark mode all screens | Matches approved dark snapshots | Not run |
| UI-046 | UI | Rotation keeps state | Open sheet and form values survive rotation | Not run |
| UI-047 | U | Large unexpected spend alert (DSH-07) | Expense > set threshold → Home alert | Not run |
| A11Y-001 | UI | Dynamic Type AX5 | Core screens usable, amounts not truncated | Not run |
| A11Y-002 | M | VoiceOver labels | Every control labelled; e.g. "Personal, over budget by Rs 1,200" | Not run |
| A11Y-003 | M | Chart summaries | Donut and bars have spoken summaries | Not run |
| A11Y-004 | UI | Colour not the only signal | Every status has word or symbol | Not run |
| A11Y-005 | M | Contrast | WCAG AA in light and dark (Accessibility Inspector, zero errors) | Not run |
| A11Y-006 | M | Reduce Motion | Springs replaced by fades | Not run |
| PRF-001 | M | Cold launch | ≤ 1.5 s to dashboard with 10k transactions (iPhone 17 Pro Max) | Not run |
| PRF-002 | M | Scrolling | Activity with 10k items without hitches (Instruments) | Not run |
| PRF-003 | M | Reports | 12-month report ≤ 1 s | Not run |
| PRF-004 | M | Voice latency | Same as VOX-015 (≤ 3 s) | Not run |
| PRF-005 | I | Search speed | Search on 10k rows ≤ 200 ms | Not run |

## 17. M12 — Release readiness (compact, §29)

| ID | Title | Expected result | Status |
|---|---|---|---|
| REL-001 | No critical known bugs | BUG_REGISTRY has no open Critical/High | Not run |
| REL-002 | Smoke suite | All SMK pass on device and CI | Not run |
| REL-003 | Regression suite | All REG pass | Not run |
| REL-004 | Financial calculations verified | All CUR, BUD, LOAN, SPL, REC, KAM, DSH-007 pass | Not run |
| REL-005 | Data migrations | DATA-024 pass from every shipped schema | Not run |
| REL-006 | Backup | DATA-020, DATA-026 pass on device | Not run |
| REL-007 | Restore | DATA-021…025 pass on device | Not run |
| REL-008 | Notifications | CAL-015, 016, 025, 026 pass on device | Not run |
| REL-009 | Calendar integration | CAL-017, CAL-018 pass on device | Not run |
| REL-010 | Permissions | All first-use prompts and denials tested | Not run |
| REL-011 | Offline | Full manual run in Airplane Mode | Not run |
| REL-012 | Device testing | Full manual checklist on iPhone (and iPad if available) | Not run |
| REL-013 | Performance | PRF-001…005 pass | Not run |
| REL-014 | Security review | SEC-001…008 pass; review notes written | Not run |
| REL-015 | Privacy | PRV-01…04 satisfied; privacy labels "Data Not Collected" | Not run |
| REL-016 | Production configuration | Release scheme, version, bundle id, no debug menus/sample default | Not run |
| REL-017 | Documentation updated | All §24 docs current | Not run |
| REL-018 | Owner approval to deploy | Explicit written approval recorded | Not run |

## 18. Bug regression tests (REG)

| ID | Bug | Title | Expected result | Status | Added in build |
|---|---|---|---|---|---|
| — | — | none yet | — | — | — |
