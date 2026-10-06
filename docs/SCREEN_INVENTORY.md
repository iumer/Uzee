# UZee: Screen Inventory and UX Specification

| | |
|---|---|
| Version | 0.1 (2026-10-06) |
| Status | Draft, awaiting user review |
| Inputs | PRD.md v0.3, tech-decisions-brief.md, mockup-dataset.md, design-audit.md, 27 approved mockups (`uzee-design/project/*.dc.html`) |
| Platform | Native SwiftUI, iOS/iPadOS 26+, universal iPhone + iPad |

The approved mockups are the UX baseline. Where this document adds something the mockups do not show, the row says **(spec)**. All sample figures come from `mockup-dataset.md` ("today" is Tue 6 Oct 2026).

Last decisions applied:
- Calendar reaches **Bills & subscriptions** through a list button in its toolbar (push).
- The **People** tab is a people-only list. Groups open from a **"Groups · 3"** button at the top of the list.
- **Kameti** and **Car installment** live inside Bills & subscriptions as "Plans" cards. They have no separate screens.

---

## 0. Global UI rules

| Rule | Detail |
|---|---|
| Tabs | iOS 26 `TabView`: Home · Activity · Budget · Calendar · People, plus a separate trailing glass **"+"** button. Each tab owns a `NavigationStack` |
| "+" button | Tap opens Add transaction (Expense). Long-press menu: Expense, Income, Transfer, Lend or borrow, Settle up, Ask UZee |
| Home toolbar | Mic → Ask UZee (sheet). Gear → Settings (push). There is no floating mic button |
| Back labels | Always name the screen you came from ("‹ People", "‹ Calendar") |
| No top segmented controls | Type, method, period and view choices use pull-down tokens ("Expense ▾"), toolbar buttons or title menus (AUD-07) |
| Money actions | Never save in one tap. They open a confirm sheet (amount, account and date editable), then show a toast "Saved · … · **Undo**" for 5 s (AUD-13) |
| Status | Never shown by colour alone: ✓ Paid, ! Overdue, "owes you" / "you owe" in words (A11Y-03) |
| Currency | USD shows native first (`$20.00`) with `≈ Rs 5,600` below. Any PKR total that includes USD carries "USD at $1 = Rs 280" |
| Tap targets | 44 pt minimum. Dynamic Type up to AX5: two-column cards stack and amounts wrap, never truncate |
| Haptics | Success haptic on save, settle and mark paid. Warning haptic on destructive confirm |
| Motion | Springs 0.35–0.5 s. The balance count-up runs only on the first open of the day. Reduce Motion is honoured |

---

## 1. Navigation hierarchy

### 1.1 iPhone

```
App launch
├── [first run] Onboarding (fullScreenCover, 5 steps) ─────────── SCR-01
│     └── "Restore a backup" → Restore (push inside cover) ─────── SCR-36
├── [app lock on] App lock (fullScreenCover, Face ID) ────────────── SCR-41
└── TabView
    ├── Tab 1 · Home  (NavigationStack) ──────────────────────────── SCR-02
    │   ├── toolbar mic  → Ask UZee (sheet, large) ────────────────── SCR-03
    │   ├── toolbar gear → Settings (push) ─────────────────────────── SCR-04
    │   │     ├── Accounts (push) ─────────────────────────────────── SCR-30
    │   │     ├── Currency & rate (inline expanding row)
    │   │     ├── People & groups → switches to People tab
    │   │     ├── Categories & tags (sheet) ───────────────────────── SCR-39
    │   │     ├── Siri & voice (sheet) ────────────────────────────── SCR-40
    │   │     ├── Back up now (push) ───────────────────────────────── SCR-35
    │   │     ├── Restore from backup (push) ───────────────────────── SCR-36
    │   │     ├── Export PDF or CSV (sheet) ────────────────────────── SCR-38
    │   │     ├── Import bank statement PDF (push) ─────────────────── SCR-34
    │   │     ├── Recently Deleted (push) ──────────────────────────── SCR-37
    │   │     └── Replay onboarding (fullScreenCover) ──────────────── SCR-01
    │   ├── Overdue strip "Pay" → Mark paid (sheet, medium) ──────────── SCR-16
    │   ├── Balance card → Accounts (push) ─────────────────────────── SCR-30
    │   │     └── Account detail (push) ───────────────────────────── SCR-31
    │   │           ├── Adjust balance (sheet, medium) ─────────────── SCR-32
    │   │           ├── Transfer (sheet, large) ────────────────────── SCR-06
    │   │           └── Import statement (push) ────────────────────── SCR-34
    │   ├── Budget card → switches to Budget tab
    │   ├── Upcoming row → Mark paid (sheet) ───────────────────────── SCR-16
    │   ├── Upcoming "See all" → Bills & subscriptions (push) ──────── SCR-17
    │   ├── Owed / You owe cards → switches to People tab
    │   ├── Donut / Insights → Reports (push) ──────────────────────── SCR-29
    │   └── Backup nudge → Backup (push) ───────────────────────────── SCR-35
    ├── Tab 2 · Activity (NavigationStack) ────────────────────────── SCR-08
    │   ├── row → Transaction detail (push) ───────────────────────── SCR-09
    │   │     ├── Edit (in place, toolbar Done/Cancel)
    │   │     ├── Repeat (sheet, medium) ───────────────────────────── SCR-10
    │   │     ├── Split row → Group (push) ─────────────────────────── SCR-22
    │   │     └── Delete (confirmation) → toast → Recently Deleted
    │   ├── row "…" → action sheet: Edit · Split · Change category · Repeat · Delete
    │   └── toolbar filter → filter menu (Show only / By account / By category …)
    ├── Tab 3 · Budget (NavigationStack) ──────────────────────────── SCR-11
    │   ├── title menu → month picker (Earlier months in Reports)
    │   ├── toolbar Edit → Budget limits (push) ───────────────────── SCR-13
    │   ├── toolbar chart → Reports (push) ────────────────────────── SCR-29
    │   ├── category row → Category drill-down (sheet, large) ─────── SCR-12
    │   │     └── transaction → Transaction detail (push) ─────────── SCR-09
    │   └── Office group row → Group (push) ───────────────────────── SCR-22
    ├── Tab 4 · Calendar (NavigationStack) ────────────────────────── SCR-14
    │   ├── toolbar Today
    │   ├── toolbar list button → Bills & subscriptions (push) ────── SCR-17
    │   │     ├── Add recurring (sheet, large) ─────────────────────── SCR-18
    │   │     ├── subscription row → Subscription detail (push) ───── SCR-19
    │   │     │     └── Edit (sheet, large)
    │   │     ├── Kameti card → "Pay contribution #5" → Mark paid ──── SCR-16
    │   │     ├── Car installment card → "Pay installment #15" → Mark paid
    │   │     └── Office group bills → Group (push) ───────────────── SCR-22
    │   ├── toolbar view menu → Month · Agenda list
    │   ├── toolbar "+" → New reminder (sheet, medium) ────────────── SCR-15
    │   └── day row → Mark paid sheet / Transaction detail / Person / Group
    └── Tab 5 · People (NavigationStack) ──────────────────────────── SCR-20
        ├── "Groups · 3" button → reveals Groups section at top of list
        │     └── group row → Group (push) ────────────────────────── SCR-22
        │           ├── Settle up (sheet, medium) ──────────────────── SCR-23
        │           ├── Remind (sheet → share sheet) ───────────────── SCR-25
        │           └── toolbar "+" → Split expense (Add sheet) ────── SCR-07
        ├── person row → Person (push) ───────────────────────────── SCR-21
        │     ├── Record repayment / Lend more / Borrow (sheet) ──── SCR-24
        │     ├── Settle up (sheet) ────────────────────────────────── SCR-23
        │     ├── Remind (sheet) ───────────────────────────────────── SCR-25
        │     └── "…" → Add shared expense · Write off balance…
        └── toolbar "+" menu: New group (SCR-26) · Add person (SCR-27)
                              · Add existing balances (SCR-28) · Add shared expense

"+" button (all tabs) → Add transaction (sheet, medium ↔ large) ─────── SCR-05
    ├── type token "Expense ▾" → Expense · Income · Transfer · Lend or borrow · Settle up
    ├── Transfer → Transfer layout (same sheet) ──────────────────────── SCR-06
    └── "Split" row → Split expense (push inside sheet, large) ───────── SCR-07
          └── With / Paid by pickers (sheet over sheet, large)

System entry points (SCR-42)
    Notification "Mark paid" → in-notification confirm · "Open" → Subscription / item
    Widget small → Budget tab · Widget medium → Bills · "Paid" button → confirm
    Control Center / Lock Screen / Action Button: Ask UZee → SCR-03 · Quick add → SCR-05
    Siri "Ask UZee …" → answer snippet / confirmation snippet
```

### 1.2 iPad (NavigationSplitView, `iPad.dc.html`)

| Sidebar item | Content column | Detail column |
|---|---|---|
| Home | Dashboard in two columns (balance, budget, spent in row 1; salary forecast + upcoming; people + donut) | none |
| Activity | Activity list with search and filter | Transaction detail (SCR-09) |
| Budget | Budget overview | Category drill-down (SCR-12) |
| Calendar | Month grid | Day list with Mark paid actions |
| People | People list ("Groups" section on top when shown) | Person (SCR-21) or Group (SCR-22) |
| Reports | Reports | none |
| Bills & subscriptions | Bills hub | Subscription detail / plan schedule |
| Accounts | Accounts list | Account detail (SCR-31) |
| Settings | Settings list | Selected settings page |

- Add transaction, Transfer, Mark paid, Settle up and all forms show as **form sheets**. Ask UZee is a toolbar button in every column.
- Sidebar can be hidden ("Hide sidebar") and works in Split View and Slide Over. Portrait collapses to two columns, and compact width falls back to the iPhone TabView.
- Toolbar also offers Hide amounts and Face ID lock toggles, which mirror Settings.

---

## 2. Screen inventory

Presentation key: **Push** = NavigationStack push · **Sheet M/L** = sheet with medium / large detent · **Cover** = fullScreenCover · **Dialog** = confirmationDialog or alert.

| ID | Screen | Mockup | Entry points | Primary action | Secondary actions | PRD IDs | States (Empty / Loading / Error) | Presentation |
|---|---|---|---|---|---|---|---|---|
| SCR-01 | Onboarding (5 steps: Welcome, Currencies, Accounts, Income, Head start) | Onboarding | First launch; Settings › Replay onboarding | Continue / Finish | Back; Restore a backup; Add a bank, wallet or card; Import statements; Explore with sample data | ACC-01, ACC-06, CUR-01, CUR-03, REC-05, LOAN-08, IMP-05, DATA-04, PRV-03 | E: n/a · L: none · Err: "! Enter a rate" on a missing USD rate; account total shows "!" | Cover |
| SCR-02 | Home | Main, HomeDark | Tab 1; app launch | Open the item that needs attention (overdue **Pay**) | Mic, gear, balance → Accounts, Budget, Upcoming rows → Mark paid, See all → Bills, Owed/Owe → People, donut/Insights → Reports, Back up now, dismiss alerts | DSH-01…07, OBJ-1, CUR-04, BUD-04 | E: "No accounts yet · Add an account" · L: skeleton cards · Err: "Couldn't load your data · Try again" | Tab root |
| SCR-03 | Ask UZee | Voice | Home mic; "+" long-press; Control Center; Action Button; Siri | Speak or type a request | Suggestion chips, Edit card rows, Save, Saved · View Usama, Pay gas bill, Open Calendar, Undo | VOX-01…08 | E: idle prompt "Ask about your money, or log something" · L: Listening… / Thinking… · Err: "Voice isn't available · Use the keyboard instead"; mic denied · Open Settings | Sheet L |
| SCR-04 | Settings | Settings | Home gear | Change a setting | Accounts, Currency & rate, Budget period, Salary day, Budget warning, People & groups, Categories & tags, Default reminder, Add dues to iPhone Calendar, Siri & voice, Back up, Restore, Export, Import, Recently Deleted, Sample data, Replay onboarding | SET-01…04, CUR-03, BUD-01, BUD-04, CAL-04, CAL-06, DATA-02…04 | E: n/a · L: none · Err: Calendar permission denied caption · Open Settings | Push (Home) |
| SCR-05 | Add transaction (Expense, Income, Lend or borrow, Settle up) | AddTransaction | "+"; Quick add control; Voice "Edit" | Save | Type ▾, account ▾, date ▾, payee or note with suggestions, receipt, category chips, All categories…, Add category, Split row, Cancel (Discard?) | TXN-01, TXN-02, TXN-06, CAT-03, LOAN-02, LOAN-05, SPL-08, ATT-01, AI-01, AI-02, OBJ-3 | E: n/a · L: none · Err: inline hint "Enter an amount and pick a category"; Save disabled | Sheet M (keypad) → L |
| SCR-06 | Transfer | AddTransfer | Add type ▾ Transfer; "+" long-press; Accounts toolbar; Account detail | Save transfer | From ▾, To ▾, swap, Received amount, Date ▾, Fee toggle | TXN-03, CUR-04, US-03 | Err: "From and To must be different accounts", "Enter the amount sent/received" | Sheet L |
| SCR-07 | Split expense | Split | Add › Split row; People "Add shared expense"; Group toolbar "+"; Activity action "Split" | Done (enabled at Rs 0 left) | With ▾ picker, four quick options, More options: Paid by ▾, Split ▾ method, member toggles, steppers | SPL-02…06, SPL-10, BUD-07 | Err: "Include at least one person"; "Rs X left to assign" (Done disabled) | Push inside Add sheet (L) |
| SCR-08 | Activity | Activity, ActivityDark | Tab 2; Budget drill-down; Import "See in Activity" | Open a transaction | Search, filter menu, tokens, row "…" (Edit, Split, Change category, Repeat, Delete), swipe Repeat/Delete | TXN-04, TXN-05, TXN-07, CUR-04, SPL-05 | E: "No transactions yet · Add one" (spec); search: "Nothing matches "x" · Clear search and filters" · L: skeleton rows · Err: Try again | Tab root |
| SCR-09 | Transaction detail (+ edit) | TxnDetail | Activity row; Budget drill-down; Group activity; Person history; Account detail; Calendar paid row | Edit | Repeat, Delete, receipt full size, linked Group / Budget, Recently Deleted link after delete | TXN-02, TXN-04, TXN-07, ATT-01, AI-02, SPL-05 | Err: "Enter an amount and a payee to save."; record deleted elsewhere → "This transaction was deleted · Recently Deleted" | Push |
| SCR-10 | Repeat transaction | Activity, TxnDetail | Detail toolbar Repeat; Activity "…" Repeat | Save | Amount, Account ▾, Date ▾ | TXN-07 | Err: amount > 0 | Sheet M |
| SCR-11 | Budget | Budget | Tab 3; Home Budget card | Open a category | Month title menu, Edit, Reports, over-budget line, Rs 3,000 unassigned → Assign, Office group → Group | BUD-01…07, RPT-03 | E: "No budget for October · Set a budget" · L: skeleton · Err: Try again | Tab root |
| SCR-12 | Category drill-down | Budget | Budget category row; over line | Open a transaction | 6-month chart, Still due this month (→ Calendar), Done | BUD-03, BUD-06, SPL-05 | E: "Nothing spent here yet this month." | Sheet L |
| SCR-13 | Budget limits | BudgetLimits | Budget Edit / Assign; Empty state "Set a budget" | Done | Total, per-category steppers, Use / Use all suggestions, Office group budget, Warn me at ▾, Budget period ▾ | BUD-01, BUD-02, BUD-04, BUD-05, BUD-07 | Err: "! Below committed bills: Rs X" (warning, not blocking); "Every rupee assigned" | Push |
| SCR-14 | Calendar (Month / Agenda) | Calendar | Tab 4 | Tap a day / due item | Today, Bills list button, view menu, "+", ‹ › month, row ⇆ Paid/Skip, swipe | CAL-01…05, REC-08, DSH-04, OBJ-2 | E: "Nothing due on this day." / "Nothing due today. Next: Internet · Nayatel, Thu 8 Oct." · out of range: "No sample data for …" · Err: calendar access off | Tab root |
| SCR-15 | New reminder | Calendar | Calendar "+" | Add | Title, Amount (optional), Date, Repeat ▾, Remind me ▾ | CAL-03, CAL-04 | Err: "! Add a title first." | Sheet M |
| SCR-16 | Mark paid | MarkPaid | Home alert/Upcoming; Calendar; Bills; Subscription; Voice; widget; Siri | Pay Rs X | Item ▾, Amount, From account ▾, Date paid ▾, Skip this time, Snooze 1 day, Undo | REC-02, REC-08, KAM-03, LOAN-06, US-07 | Err: amount > 0; status lines "Overdue · was due Mon 5 Oct" | Sheet M |
| SCR-17 | Bills & subscriptions (incl. Kameti + Car installment) | Bills | Calendar list button; Home See all; Reports tile; widget medium; iPad sidebar | Mark an item paid | Add recurring, row → Subscription / Mark paid, Plans: Kameti strip, Car schedule (36), Show/Hide details, Set up again… | REC-01…08, KAM-01…04, LOAN-06, RPT-04 | E: "No recurring items yet · Add recurring" (spec) · Paused/cancelled: "Nothing paused right now." · Err: kameti mismatch "! Payouts (Rs 300,000) don't match contributions (Rs 240,000). Check figures with the committee." | Push |
| SCR-18 | New recurring item | Bills | Bills "+" / Add recurring | Save | All REC-01 fields | REC-01, REC-03, KAM-01, LOAN-06, SPL-03 | Err: "! Add a name and an amount." | Sheet L |
| SCR-19 | Subscription detail (+ Edit) | Subscription | Bills row; notification Open | Mark paid · Rs 1,100 | Edit, Reminder ▾, Show in iPhone Calendar, Pause for a month, Mark as cancelled / Reactivate, price history | REC-03, REC-04, CAL-04, CAL-06 | Cancelled state: Reactivate | Push |
| SCR-20 | People | People | Tab 5; Home owed cards; Settings People & groups | Open a person | Groups · 3 toggle, "+" menu (New group, Add person, Add existing balances, Add shared expense), row quick sheet (Remind, Settle up) | LOAN-01, LOAN-04, SPL-01, SPL-07, DSH-06 | E: "No people yet · Add a person" · L: skeleton · search none: "No one called "x"" (spec) | Tab root |
| SCR-21 | Person (e.g. Usama) | Person | People row; Voice "Saved · View Usama"; Reports; Calendar follow-up | Record repayment | Lend more / Borrow, Settle up, Remind, Follow-up reminder ▾, Due date ▾, Interest, "…": Add shared expense, Write off balance… | LOAN-01…05, LOAN-07, SPL-01, SPL-08, SPL-11 | Settled: "✓ All settled. Nothing to settle or remind." | Push |
| SCR-22 | Group (e.g. Office) | Group | People Groups; Budget; Bills; TxnDetail split; Reports | Settle up | Month title menu, Remind, Add shared expense, activity rows, Upcoming | SPL-02, SPL-07…12, BUD-07, RPT-06 | Settled: "✓ All settled"; empty month: "No shared expenses in this month" (spec) | Push |
| SCR-23 | Settle up | People, Group, Person, AddTransaction | Group / Person / People quick sheet; Add type "Settle up"; iPad Calendar | Save settlement | Amount (partial), From/Into ▾, Date ▾, Use full | SPL-08, LOAN-03 | Err: "More than the balance of Rs X"; "Enter an amount" | Sheet M |
| SCR-24 | Record repayment / Lend more / Borrow | Person | Person buttons | Save repayment / Save | Quick amounts Rs 5,000 · Rs 10,000 · Full · Custom; Type ▾; account ▾; date ▾ | LOAN-02, LOAN-03, LOAN-05 | Err: "Enter an amount"; "More than the balance of…" | Sheet M |
| SCR-25 | Remind (message) | Person, Group, People | Remind buttons | Send via Messages / Mail / Copy / More | Edit text | SPL-11, LOAN-07 | Done: "Message copied" / "Opened in Messages" | Sheet M → share sheet |
| SCR-26 | New group | People | People "+" › New group | Create | Name, Icon, Members, Default split ▾ | SPL-02 | Err: name and ≥ 1 member required | Sheet L |
| SCR-27 | Add person | People, EmptyStates | People "+"; empty state; Split picker "Add "x"" | Add | Add existing balances instead | LOAN-01 | Err: name required | Sheet M |
| SCR-28 | Existing balances | People | People "+"; Onboarding step 5 | Save | Rows: Person, direction ▾, amount; + Add another person; × remove | LOAN-08 | Err: incomplete rows are ignored, with a note | Sheet L |
| SCR-29 | Reports | Reports | Home donut / Insights; Budget toolbar; iPad sidebar | Change period | Period ▾ (Custom… sheet), PDF (preview → Share: Mail, Messages, Save to Files, Print), drill-ins to Budget, Bills, Group, Person, Accounts | RPT-01…09 | E: "Not enough history yet" (spec) · L: chart placeholders · Err: PDF failed toast | Push |
| SCR-30 | Accounts | Accounts | Home balance card; Settings › Accounts | Open an account | Transfer, Add account "+" (spec), Archived section › Unarchive | ACC-01…05, CUR-04 | E: "No accounts yet · Add an account" | Push |
| SCR-31 | Account detail | Accounts | Accounts row | Adjust balance | Transfer, Import statement, Archive, Include in totals toggle, transactions | ACC-03, ACC-04, ACC-05, RPT-07 | E: "No October transactions in this account yet." | Push |
| SCR-32 | Adjust balance | Accounts | Account detail | Save adjustment | Actual balance, Account ▾, Date ▾ | ACC-04 | "Balance already matches" (Save disabled) | Sheet M |
| SCR-33 | New account | Onboarding | Onboarding step 3; Accounts "+" (spec) | Add | Name, Type, Currency, Current balance | ACC-01, ACC-02 | Err: name required | Sheet M |
| SCR-34 | Statement import (3 steps) | Import | Settings; Account detail; Onboarding step 5 | Import N transactions | Account, file picker, Cancel reading, row toggles, category ▾, Send sample, Import another, See in Activity | IMP-01…06 | L: "Reading HBL_Sep2026.pdf…" · Err: "Couldn't read this statement" / "Unsupported format · Send sample" | Push |
| SCR-35 | Backup | Backup | Settings › Back up now; Home nudge | Save to Files | Password ×2, location ▾ | DATA-02, SEC-03 | Err: "Use at least 8 characters.", "Set the password twice first" | Push (+ Sheet M) |
| SCR-36 | Restore (3 steps) | Backup#restore | Settings › Restore; Onboarding welcome | Replace all data… | Choose another file, Cancel | DATA-02, DATA-05, US-11 | Err: wrong password "Enter the backup password"; damaged file (spec) | Push |
| SCR-37 | Recently Deleted | Backup#deleted | Settings; TxnDetail delete toast | Restore | Delete now | DATA-01, TXN-04 | E: "Nothing recently deleted · Deleted transactions wait here for 30 days." | Push |
| SCR-38 | Export | Settings | Settings › Export PDF or CSV | Export {format} | Period ▾, Accounts ▾, Format (PDF / CSV) | DATA-03, RPT-09 | Err: export failed toast | Sheet M |
| SCR-39 | Categories & tags | Settings | Settings | Done | Category list (rename, reorder, hide, merge: spec), Tags | CAT-01, CAT-02, CAT-04 | E: "No tags yet. Add a tag from any transaction's detail." | Sheet L |
| SCR-40 | Siri & voice | Settings | Settings | Try Ask UZee | App Shortcuts list, Action Button, Control Center help, See the controls | VOX-01, VOX-08 | Err: Apple Intelligence off → fallback explanation | Sheet L |
| SCR-41 | App lock **(spec)** | none | Launch / return when Face ID lock is on | Unlock with Face ID | Use passcode | SET-01, SET-02, SEC-02 | Err: Face ID failed → passcode | Cover |
| SCR-42 | System surfaces | Notifications | iOS | Mark paid / Snooze 1 day / Open | Widgets (small, medium with Paid), Lock Screen and Control Center controls, Siri answer and confirm snippets | §15, VOX-01, SEC-04, REC-08 | Hidden amounts when app lock is on ("Rs •••••") | System |
| SCR-43 | Empty, loading, error catalogue | EmptyStates | Reference | — | — | AUD-32, A11Y | All patterns in §8 | Reference |
| SCR-44 | iPad layout | iPad | iPad | — | — | NFR-02 | — | SplitView |

---

## 3. Screen relationships

| From | To | Trigger | Data passed |
|---|---|---|---|
| Home overdue strip / Upcoming row | Mark paid | Pay / row tap | Recurring occurrence id |
| Home See all · Calendar list button | Bills & subscriptions | Push | — |
| Bills Plans (Kameti / Car) | Mark paid | "Pay contribution #5 · Rs 20,000" / "Pay installment #15 · Rs 45,000" | Plan occurrence id |
| Bills subscription row | Subscription detail | Push | Recurring item id |
| Add transaction | Split | "Split · Not split" row | Draft amount, category, payee, date |
| Add transaction | Transfer | Type ▾ › Transfer | Draft amount, date |
| Activity / Budget drill / Group / Person / Account | Transaction detail | Row tap | Transaction id |
| Transaction detail | Group / Budget | Linked rows | Group id, category id |
| People Groups section | Group | Row tap | Group id |
| People row | Person | Row tap | Person id |
| Voice confirmation card | Person | "Saved · View Usama" | Person id |
| Import Done | Activity | "See in Activity" | Import batch filter |
| Delete toast / Settings | Recently Deleted | Link | — |
| Settings Accounts · Home balance | Accounts → Account detail | Push | Account id |
| Notification "Open" | Subscription detail (or item screen) | Deep link `uzee://recurring/<id>` | Occurrence id |
| Widget medium · Siri "Open Bills" | Bills & subscriptions | Deep link | — |

Every edit anywhere updates Home, Budget, Calendar, People and Reports through repository observation, with no manual refresh.

---

## 4. User journeys

Screens are referenced by ID. Figures from mockup-dataset.md.

### J1 · First-run onboarding
1. First launch opens **Onboarding step 1 · Welcome** (SCR-01): "Everything stays on this iPhone". Tap **Continue**. (Alternative: "Moving from another iPhone? Restore a backup" → SCR-36.)
2. **Step 2 · Your currencies**: Base currency **PKR ▾**. Turn on **USD** under "I also use" and enter rate `1 USD = 280 PKR`. Continue.
3. **Step 3 · Your accounts**: preset toggles in Banks (HBL, Meezan), Cash, Wallets & cards (Easypaisa, SadaPay, NayaPay, Wise, Fasset, RedotPay). Enter each balance and pick currency ▾ (Wise $520, Fasset $95, RedotPay $45). The footer reads "9 accounts · total today in PKR · Rs 484,800 · Rs 300,000 + $660 · $1 = Rs 280". "Add a bank, wallet or card" opens SCR-33.
4. **Step 4 · Your income**: Salary **$1,875**, paid on **the 21st** ▾, into **Wise** ▾, Remind me on payday on. Preview: "Next salary · Wed 21 Oct · $1,875.00 ≈ Rs 525,000".
5. **Step 5 · A head start** (all optional): Add people balances (Usama owes you Rs 25,000 … Ammi you owe Rs 75,000), Import statements (→ SCR-34), Explore with sample data.
6. Tap **Finish** (or "Finish with sample data") → Home. Notification, Calendar and Siri permissions are asked later, the first time each is used.

### J2 · Add an expense
1. Tap **"+"** → Add transaction (SCR-05) opens at the medium detent: type **Expense ▾**, account **HBL · PKR ▾** (last used), date **Today ▾**.
2. Type `14517` on the keypad (PKR has a "000" key; USD accounts show a "." key instead).
3. Tap the payee field and pick the suggestion **Shell, Gulberg** (it sets **Fuel · Transport**), or tap the **Fuel** chip.
4. Optional: tap 📎 to attach a receipt. On-device reading fills the amount and date.
5. **Save** (enabled once amount > 0 and a category is picked). The sheet closes, a success haptic plays, and the toast reads "Saved · Shell, Gulberg Rs 14,517 · Undo".
6. Activity shows the row under "Today · Tue 6 Oct". Home Spent and Budget Transport update.

### J3 · Add a split expense
1. "+" → amount `3200`, account **Cash**, category **Office refreshments**, payee "Office tea & snacks".
2. Tap the **Split · Not split** row → Split (SCR-07, pushed, large detent).
3. **With ▾** opens the picker ("Type a name or group"). The Groups section lists Office, Hunza trip, Home groceries. "People · pick one or more" lists people with their balances. Pick **Office** → Done.
4. **Who paid, and how to split** shows four quick options for a two-person split:
   - (a) **You paid, split equally**: Office partner owes you Rs 1,600
   - (b) **You are owed the full amount**: Office partner owes you Rs 3,200
   - (c) **Office partner paid, split equally**: You owe Office partner Rs 1,600
   - (d) **Office partner is owed the full amount**: You owe Office partner Rs 3,200
   Pick (a). "Your share Rs 1,600 · Only your share counts toward your budget." For 3+ members only (a) and "Someone else paid, split equally · Choose who paid" appear.
5. *Pick a person instead*: in With ▾, type "Us" → **Usama** → ✓ → Done.
6. *New person*: type "Hamza" → "No one called "Hamza" yet." → **+ Add "Hamza" as a new person** → chip "Hamza ×" → Done. The person record is created when the transaction saves.
7. *More options* (unequal amounts, %, shares, someone from your list or several payers): **Paid by ▾** (You · Cash / Pick from list… / Multiple), **Split ▾** (Equally / Exact / Percent / Shares). Toggle members, type amounts or use share steppers. The live line reads "Rs X left to assign" and **Done** stays disabled until it shows "✓ Rs 0 left to assign".
8. **Done** → back to Add, where the row reads "Split · Office group, equally". **Save** → toast with Undo. The Office group balance becomes "you owe Office partner Rs 9,800".

### J4 · Transfer Wise → HBL with the actual rate
1. Long-press "+" → **Transfer** (or Add › Expense ▾ › Transfer, or Accounts › Transfer).
2. **From Wise ▾** (USD · $520.00), **To HBL ▾** (Bank · Rs 182,400). The ⇅ button swaps them.
3. **Sent $** `500.00`. **Received Rs** `139,350`.
4. The rate line computes **278.70** and shows "Rs 650 less than at 280". With equal amounts it reads "Same as the table rate (280)".
5. **Date ▾** Yesterday (Mon 5 Oct). Optional **Fee**: an amount posts as a separate Financial › Transfer fees expense.
6. **Save transfer · $500.00 → Rs 139,350** → toast "Transfer saved · Undo". Activity shows "Wise → HBL · $500 → Rs 139,350 · 278.70", which is not spending.

### J5 · Lend to Usama by voice
1. Home → **mic** → Ask UZee (SCR-03) → tap mic (state **Listening…**).
2. Say "I sent 20k to a friend, they'll return it later." → **Thinking…** → "Who did you lend it to?"
3. Say "Usama". UZee: "Usama already owes you Rs 5,000. Add Rs 20,000? New balance Rs 25,000." Then: "When should I remind you?" Chips: Usama, Bilal, New person / End of the month, No reminder.
4. Say "End of the month." UZee: "I'll remind you on Sat 31 Oct at 10:00. Here's the loan. Change any row, then save."
5. The confirmation card **New loan · check and save** shows Lend Rs 20,000 ▾, To Usama ▾, From Easypaisa ▾, Date Today ▾, Remind 31 Oct ▾ and "New balance Usama owes you Rs 25,000". Every row is a picker.
6. **Save** → "Saved · View Usama" with Undo. Easypaisa is debited Rs 20,000 (not spending), and the follow-up appears in Calendar on Sat 31 Oct.
7. If the name is unknown, UZee answers "X is new. I'll add them to People, owing you Rs 20,000." If on-device AI is unavailable, the card is replaced by "Voice isn't available · Use the keyboard instead".

### J6 · Record a repayment
1. People → **Usama** (owes you Rs 25,000 · Loans Rs 25,000 · shared Rs 0).
2. Tap **Record repayment** → sheet (SCR-24) "Usama paid you back". Quick amounts: Rs 5,000 · Rs 10,000 · Full · Custom.
3. Pick **Rs 5,000**, **Into Easypaisa ▾**, **Date Today ▾**. Hint: "New balance: Usama owes you Rs 20,000".
4. **Save repayment** → toast "Repayment saved · Undo". History adds "Repaid to you · Today · Easypaisa". The Calendar follow-up amount updates.

### J7 · Mark a bill paid from a notification
1. Sun 11 Oct 10:00: "UZee · Netflix Rs 1,100 due tomorrow · Mon 12 Oct · HBL card". With app lock on it reads "amount hidden".
2. Touch and hold → actions **Mark paid ✓ · Snooze 1 day ◷ · Open ↗**.
3. **Mark paid** → inline confirm "Mark Netflix paid? Amount Rs 1,100 · Account HBL card · Date Today, Sun 11 Oct" → **Confirm**. Face ID is required while app lock is on.
4. Result: "Saved · Netflix Rs 1,100 paid from HBL card" with Undo. Next renewal moves to Thu 12 Nov.
5. Alternatives: **Snooze 1 day** → "Snoozed · we'll remind you Mon 12 Oct at 10:00". **Open** → Subscription detail (SCR-19) → "Mark paid · Rs 1,100" → Mark paid sheet (SCR-16), where the amount can be edited.

### J8 · Set the budget and the salary-cycle period
1. Budget tab → **Edit** → Budget limits (SCR-13).
2. **Total budget Rs** `235,000`. Set each category with ± (steps of Rs 1,000), or tap **Use** per row or **Use all suggestions** (from September spend plus committed bills). The line reads "Rs 3,000 unassigned · limits Rs 232,000".
3. If a limit is below committed bills, the row shows "! Below committed bills: Rs 14,065". This is a warning only.
4. **Office group · whole group** Rs 150,000 (does not count toward your total).
5. **Warn me at 80% used ▾** (70% earlier heads-up · 80% default · 90% later heads-up).
6. **Budget period ▾** → **Salary cycle (21st → 20th)**. Caption: "Budget runs 21 Oct – 20 Nov. Salary cycle starts on salary day ($1,875 on the 21st). The current month stays on the calendar until then."
7. **Done** → toast "Saved · Undo". Settings › Budget period shows the same value. New months copy these limits automatically.

### J9 · Review an overspend
1. Home Budget card shows "! Personal over by Rs 1,200". Tap → Budget tab.
2. Budget shows "! Personal is over budget by Rs 1,200". Tap it (or the Personal row) → drill-down (SCR-12): "Rs 6,200 of Rs 5,000 · October so far", 6-month bars against the limit, October transactions: **Daraz Rs 6,200 · Sun 4 Oct · Clothing · Meezan**.
3. Tap Daraz → Transaction detail. Fix it (Edit, or "…" › Change category) or accept it.
4. Optional: Budget **Edit** → raise Personal to Rs 7,000 → Done. The over line disappears and Home updates.

### J10 · Settle up the Office group
1. People → **Groups · 3** → **Office** (Group, SCR-22). Balance now: "You owe Office partner Rs 9,800". Title menu: October 2026.
2. Optional **Remind** → message prefilled with the October summary → Messages / Mail / Copy / More.
3. Tap **Settle up** → sheet "You pay Office partner": Amount Rs `9,800` (editable, partial is fine), **From HBL ▾**, **Date Today ▾**. The hint reads "Settles the full balance of Rs 9,800".
4. **Save settlement** → toast "Settled · Undo". Group shows "✓ All settled". The People total "You owe" drops to Rs 78,200, and the Calendar "Settle up: Office group" item clears.

### J11 · Import a bank PDF
1. Settings → **Import bank statement PDF** (or Account detail › Import statement).
2. **Step 1 of 3 · Choose account** → HBL. "Rows are added to this account. Transfers to your other accounts are spotted and left out."
3. **Step 2 of 3 · Pick the PDF** → Files › Downloads › **HBL_Sep2026.pdf** → **Read statement**. A reading state follows ("Finding dates, amounts and payees… Nothing leaves this iPhone.") with Cancel.
4. **Step 3 of 3 · Review**: summary, then sections **New · N** (category ▾ suggestions), **Possible duplicates · N** (off by default, "Matches in UZee: …"), **Excluded · N**. Toggle rows and change categories.
5. **Import** → confirm sheet: Into account HBL ▾, Period 1–30 Sep 2026, New transactions N, Skipped M → **Import N transactions**.
6. Done screen: "Imported" rows are marked and can be undone in one step. Options: Import another statement · See in Activity · Done.
7. Errors: "Couldn't read this statement" (scanned or password-protected) → Try another file. "Unsupported format" → Help add this bank (3 steps) → **Send sample** (Mail opens with the file, nothing sent until you tap Send).

### J12 · Back up and restore
1. Home nudge "Never backed up · Back up now" or Settings › **Back up now** → Backup (SCR-35): Last backup Never, about 2 MB, includes 9 accounts · 6 people · 3 groups · budgets, reminders, receipts.
2. Enter **Password** and **Repeat password** (at least 8 characters). Warning: "UZee can't recover it if you forget it."
3. **Save to Files** → sheet: Name `UZee-backup-2026-10-06.uzee`, Location **iCloud Drive › UZee ▾** → Save. Toast; Last backup shows Today; the Home nudge disappears.
4. Restore (new phone or Settings › **Restore from backup**): **Step 1** pick the .uzee file → **Step 2** enter its password → **Unlock backup** → **Step 3** summary (Created Tue 6 Oct 2026 · Accounts 9 · People · groups 6 · 3 · Recently Deleted 3) with "! Everything currently on this iPhone is replaced."
5. **Replace all data…** → alert "Replace all data?" → **Replace**. UZee makes an automatic safety copy first, restores, and reopens Home.

### J13 · Restore a deleted transaction
1. *Immediately*: after Delete in Transaction detail, the banner "Moved to Recently Deleted · Kept for 30 days…" offers **Undo**.
2. *Later*: Settings → **Recently Deleted · 3 items** (SCR-37) → row "Careem · Rs 640 · Transport › Ride-hailing · deleted Fri 2 Oct · 26 days left".
3. Tap **Restore** → toast "Restored · Undo". The row returns to Activity, its account, budget and any group balance.
4. **Delete now** asks "Delete "Careem" now? It's removed for good and can't be restored." → Delete.

---

## 5. Forms

Common rules: amounts are typed as text and parsed to Int64 minor units. PKR has no decimals (keypad "000" key) and USD allows 2 decimals ("." key). Amounts must be > 0 and at most 9 digits. Dates are picked from a menu (Today, Yesterday, recent days, Custom…). Save stays disabled until the form is valid, with an inline hint explaining why.

| Form (screen) | Fields | Validation | Defaults |
|---|---|---|---|
| Expense / Income (SCR-05) | Amount; Type ▾; Account ▾ (with balances); Date ▾; Payee or note (suggestions); Receipt 📎; Category (chips of frequent subcategories + "All categories…" + "Add"); Split row; Tags, Pending status **(spec, on detail edit)** | Amount > 0; category required; new category name not empty | Expense; last-used account (HBL); Today; Not split; payee's last category (CAT-03) |
| Lend or borrow (SCR-05) | Amount; Person ▾; Direction ▾ (I lent: money left my account / I borrowed: money came into my account); Account ▾; Date; Due date (optional) ▾; Follow-up reminder ▾ | Amount > 0; person required | I lent; Due None; Reminder Off; footer "Not counted as spending" |
| Settle up (SCR-05 / SCR-23) | With ▾ (people/groups with balances); Amount (Use full); Account (From / Into); Date | Amount > 0 and ≤ balance ("More than the balance of Rs X") | With = largest balance (Office partner); amount = full balance; HBL; Today |
| Transfer (SCR-06) | From ▾; To ▾; Sent; Received (only when currencies differ); Date ▾; Fee toggle + amount | From ≠ To; Sent > 0; Received > 0 when cross-currency; fee ≥ 0 | From Wise, To HBL; Today; Fee off; received prefilled at table rate as a placeholder only |
| Split (SCR-07) | With ▾; quick option; Paid by ▾ (You / one member / Multiple with amounts); Split method ▾ (Equally / Exact / Percent / Shares); member include toggles; per-member value or stepper | ≥ 1 other person included; payer amounts sum to total; shares sum to total → "Rs 0 left to assign" | Option (a) You paid, split equally; payer = You · transaction account; method from group default |
| Edit transaction (SCR-09) | Amount; Payee; Account ▾; Tags | Amount > 0, payee required ("Enter an amount and a payee to save.") | Current values; split stays equal and is recomputed |
| Repeat (SCR-10) | Amount; Account ▾ (or "Paid by Office partner · no account movement"); Date ▾ | Amount > 0 | Copies category, payee, tags and split; Today |
| Budget limits (SCR-13) | Total; per-category limit (± Rs 1,000); group budget; Warn at ▾ (70/80/90%); Budget period ▾ | Limits ≥ 0; sum may be below total (shown as unassigned) or above (shown as "over-assigned", spec) | Copy of last month; 80%; Calendar month |
| New reminder (SCR-15) | Title; Amount (optional); Date; Repeat ▾ (Never/Weekly/Monthly/Yearly); Remind me ▾ | Title required ("! Add a title first.") | Selected day; Never; 1 day before at 10:00 |
| Mark paid (SCR-16) | Item ▾; Amount; From account ▾; Date paid ▾ | Amount > 0 | Due amount (estimated ones editable); item's account; Today |
| New recurring (SCR-18) | Name; Amount; Type ▾ (Bill, Subscription, Income, Installment, Kameti, Office group bill); Amount is ▾ (Fixed/Estimated); Currency; Account ▾; Category ▾; Split with ▾; Frequency ▾ (Monthly, Weekly, Every 3 months, Yearly); Next due; End date (optional); Remind me ▾ | Name and amount required ("! Add a name and an amount.") | Fixed; PKR; HBL; Not split; Monthly; 1 day before at 10:00; Kameti/Installment add count, payouts / schedule fields (spec) |
| Edit subscription (SCR-19) | Icon (monogram/symbol) + colour; Name; Amount; Billing day; Pays from | Name, amount required | New amount applies from the next renewal and is added to price history |
| Record repayment / Lend more / Borrow (SCR-24) | Quick amount (Rs 5,000 / Rs 10,000 / Full / Custom); Type ▾; Account ▾; Date ▾ | Amount > 0; repayment ≤ balance | Repayment; Easypaisa (last used with person); Today |
| Person settings (SCR-21) | Follow-up reminder ▾; Due date ▾; Interest (optional, % per year) | Interest 0–100 | Follow-up 31 Oct; no interest |
| New group (SCR-26) | Name; Icon (People, Home, Trip, Work, Food); Members (you always included); Default split ▾ (Equally, Exact amounts, Percentages, By shares) | Name and ≥ 1 member | Equally |
| Add person (SCR-27) | Name | Not empty; duplicate name asks "Use existing Usama?" (spec) | Starts settled |
| Existing balances (SCR-28) | Rows: Person, direction ▾ (owes you / you owe), Amount; add/remove rows | Rows missing name or amount are skipped | Matching names add to that person's balance; no account movement |
| Adjust balance (SCR-32) | Actual balance; Account ▾; Date ▾ | Must differ from current ("Balance already matches") | Selected account; Today |
| New account (SCR-33) | Name; Type (Bank, Wallet, Card, Cash…); Currency (enabled ones only); Current balance; Include in totals (spec) | Name required | Bank; base currency; 0 |
| Onboarding currencies (SCR-01 step 2) | Base currency ▾; I also use (USD, EUR, GBP, AED, SAR) with rate | Rate required for each enabled currency | PKR; USD on at 280 |
| Onboarding income (step 4) | Name; Amount + currency ▾; Paid on ▾ (day); Into ▾; Remind me on payday | Amount > 0 to create | Salary; USD 1,875; 21st; Wise; on |
| Backup (SCR-35) | Password; Repeat; Location ▾ | ≥ 8 characters; both match | iCloud Drive › UZee |
| Restore (SCR-36) | File; Password | Correct password (decrypt succeeds) | — |
| Export (SCR-38) | Period ▾ (Oct so far, September 2026, Last 6 months, All time); Accounts ▾; Format (PDF / CSV) | — | September 2026; All 9 accounts; PDF |
| Custom report period (SCR-29) | From month ▾; To month ▾ | From ≤ To | Apr–Sep 2026 |
| Currency & rate (SCR-04) | $1 = Rs ___ | > 0 | 280 |
| Voice confirmation card (SCR-03) | Amount, To (person), From (account), Date, Remind | Same as Lend or borrow | Parsed from speech; missing fields asked as follow-up questions |

---

## 6. Confirmation dialogs, Undo and destructive actions

### 6.1 Undo rule
Every money action (save, edit, delete, mark paid, skip, snooze, settle, repayment, transfer, import, adjust, archive, write off, category change, limit change) shows a toast "**Saved · <what>** · Undo" for **5 s**. Undo reverts in one database transaction. A deleted record also lands in Recently Deleted (DATA-01). Undo is not offered for restore (replace all data) or permanent deletion.

### 6.2 Dialogs

| Action | Screen | Dialog | Buttons | Undo |
|---|---|---|---|---|
| Cancel with unsaved edits | Add, Transfer, Split, any edit sheet | "Discard changes? This transaction has not been saved." | Discard changes (destructive) · Keep editing | — |
| Delete transaction | TxnDetail, Activity "…", swipe | "Delete "Office tea & snacks"? Rs 3,200 · Tue 6 Oct. Your Rs 1,600 share and Office partner's Rs 1,600 come off the Office group balance. Kept in Recently Deleted for 30 days." | Delete (destructive) · Cancel | Yes + Recently Deleted |
| Delete now (permanent) | Recently Deleted | "Delete "Careem" now? It's removed for good and can't be restored." | Delete · Cancel | No |
| Archive account | Account detail | "Archive HBL? It leaves your lists and totals, including its balance of Rs 182,400. Its history stays in Activity and Reports." | Archive · Cancel | Yes (and Unarchive) |
| Write off balance | Person "…" | "Write off Rs 25,000? Usama will no longer owe you this. No account money moves. It shows in history as written off, and you can undo it." | Write off (destructive) · Cancel | Yes |
| Pause subscription | Subscription | "Pause for a month? Skips the Mon 12 Oct payment and its reminder. It renews again on Thu 12 Nov." | Pause · Cancel | Yes (Resume now) |
| Mark subscription cancelled | Subscription | "Mark as cancelled? Stops reminders and removes Rs 1,100 from monthly totals. Cancel with the provider as well." | Mark as cancelled · Cancel | Yes (Reactivate) |
| Remove sample data | Settings | "Remove sample data? Only entries labelled Sample are removed. Your own accounts and transactions stay." | Remove (destructive) · Cancel | No |
| Replace all data (restore) | Restore | "Replace all data? Everything on this iPhone is replaced with the backup from 6 Oct 2026. This can't be undone." | Replace (destructive) · Cancel | No (auto safety copy) |
| Import | Import confirm sheet | Into account · Period · New · Skipped | Import N transactions · Cancel | Yes, one step |
| Settle up / repayment / mark paid | Sheets | The sheet is the confirmation | Save · Cancel | Yes |
| Notification / widget / Siri Mark paid | System | "Mark Netflix paid? Amount · Account · Date" | Confirm · Cancel | Yes (toast in app / snippet Undo) |
| Delete person / group **(spec)** | Person / Group "…" | Allowed only at Rs 0 balance: "Delete Sara? Her history stays in transactions." | Delete · Cancel | Yes + Recently Deleted |
| Delete recurring item **(spec)** | Subscription / Bills edit | "Delete Netflix? Past payments stay; future reminders stop." | Delete · Cancel | Yes + Recently Deleted |

Accounts with transactions are never hard-deleted, only archived (ACC-05).

---

## 7. Search and filtering

### 7.1 Activity (SCR-08)
| Aspect | Behaviour |
|---|---|
| Field | Native `.searchable`, placeholder "Search payee, note, amount", clear (x) button |
| Matching | Case-insensitive substring over payee, note/meta, category path, account(s), amount (with or without thousands separators, so "14517" and "14,517" both match), your share and short date ("5 Oct"). Debounced 150 ms; GRDB FTS5 index for 10,000+ rows (PRF-02) |
| Filter button | Toolbar `line.3.horizontal.decrease`, with a badge showing the active filter count |
| Filter menu | **Show only**: Expense · Income · Transfer · Shared · Loans. **By account ›** (all 9, with row counts). **By category ›** (with counts). **(spec, TXN-05)** By person or group ›, By tag ›, Date range ›. **Clear all filters** (red, only when active) |
| Tokens | Each active filter appears as a removable token inside the search field ("HBL ×"). Values of the same kind are OR-ed; different kinds are AND-ed; text is AND-ed with tokens |
| Result line | "N results" under the field while filtered |
| Day headers | Keep the day's full "Rs X spent" (your share) even when filtered, so totals never mislead |
| No results | "Nothing matches "xyz"" or "No transactions match these filters." + **Clear search and filters** |
| Persistence | Filters reset when the tab is left for > 30 min or the app relaunches (spec) |

### 7.2 People (SCR-20) (spec, not mocked)
- `.searchable` "Search people", matching name prefix and substring. While searching, the Groups section shows matching group names too.
- No match: "No one called "x" yet" + **Add "x" as a person**.
- Sort: non-zero balances first (largest first), then settled people alphabetically. A toolbar sort menu (Balance / Name) is optional.

### 7.3 Split pickers (SCR-07)
| Picker | Behaviour |
|---|---|
| With ▾ | Search "Type a name or group". Sections **Groups** then **People · pick one or more**, each row with its balance ("owes you Rs 25,000"). Multi-select for people; picked items show as chips with ×. A group is single-select and replaces people |
| No match | "No one called "Hamza" yet." + **+ Add "Hamza" as a new person** (created on save) |
| Paid by ▾ | You (with account) · members · **Pick from list…** ("Type a name", anyone in People) · **Multiple** (enter who paid what) |

### 7.4 Other search and suggestions
| Where | Behaviour |
|---|---|
| Add payee field | Up to 4 suggestions filtered by substring, showing "Payee · Subcategory · Category". Picking one sets the category. "No match. It will be saved as typed." |
| All categories… | Two-level menu of the category tree with colours |
| Voice | Person, account and category names are fuzzy-matched to records. An unknown name offers "New person" |
| Import review | Rows are filtered by section (New, Possible duplicates, Excluded) |
| Budget | Title menu filters by month; earlier months link to Reports |
| Group | Title menu filters activity by month (October 2026, September 2026) |
| Calendar | View menu: Month / Agenda list. ‹ › change month. Today button |
| Reports | Period menu: This month, September 2026 (last full month), Last 6 months, Custom… |

---

## 8. Empty, loading and error states

One pattern, built on `ContentUnavailableView`: symbol, title, one-line text, one action.

| Context | Title | Text | Action |
|---|---|---|---|
| Home, no accounts | No accounts yet | Add the bank, wallet and USD accounts you use. Your balance and what's due before salary appear here. | Add an account |
| Budget, none set | No budget for October | Set a monthly total and limits per category. Your spending still counts while you decide. | Set a budget |
| Activity, no results | No results for "x" | — | Clear search and filters |
| Activity, no data (spec) | No transactions yet | Add an expense or import a statement. | Add transaction |
| People, none | No people yet | Add someone you lend to, borrow from or split bills with. Each person gets one balance. | Add a person |
| Calendar day | Nothing due on this day. / Nothing due today. Next: Internet · Nayatel, Thu 8 Oct. | — | — |
| Budget drill-down | Nothing spent here yet this month. | — | — |
| Account detail | No October transactions in this account yet. | — | — |
| Recently Deleted | Nothing recently deleted | Deleted transactions wait here for 30 days. | — |
| Tags | No tags yet. Add a tag from any transaction's detail. | — | — |
| Voice unavailable | Voice isn't available | Speech recognition isn't available on this iPhone right now. You can still type your question. | Use the keyboard instead |
| Mic denied | Microphone access is off | Allow UZee to use the microphone in Settings. Speech is processed on this iPhone. | Open Settings |
| Calendar denied | Calendar access is off | To show your iPhone calendar events next to bills and add reminders there, UZee needs Full Access. | Open Settings |
| Import failed | Couldn't read this statement | The PDF may be scanned or password-protected. Nothing was imported. | Try another file |
| Import unsupported | This format isn't supported yet | Send a sample with the amounts hidden and we'll add support for it. Nothing was imported. | Send a sample |
| Generic load error (spec) | Couldn't load your data | Your data is safe on this iPhone. | Try again |
| Save error (spec) | Alert "Couldn't save" | Nothing was changed. Try again. | OK |

**Loading**: data is local, so loading is usually instant. Show skeleton placeholders only if a query takes longer than 300 ms, keeping the layout steady; Reduce Motion stops the shimmer. Long jobs (statement reading, backup, restore, PDF export) show a progress state with Cancel where it is safe.

---

## 9. ASCII wireframes

Samples use mockup-dataset.md. `▾` = menu token, `›` = push, `[ ]` = button, `(mic)`, `(gear)`, `(+)` = toolbar glass buttons.

### 9.1 Home (SCR-02)
```
┌──────────────────────────────────────────────┐
│ TUESDAY, 6 OCTOBER              (mic) (gear) │
│ Home                                         │
│ ┌──────────────────────────────────────────┐ │
│ │ ! 1 overdue  Gas bill · SNGPL      [Pay] │ │
│ │   Rs 3,250 · Estimated · was due Mon 5 ✕ │ │
│ └──────────────────────────────────────────┘ │
│ ┌──────────────────────────────────────────┐ │
│ │ Available balance                        │ │
│ │ Rs 484,800                               │ │
│ │ Rs 300,000 + $660 · USD at 280           │ │
│ │ 9 accounts                             › │ │
│ └──────────────────────────────────────────┘ │
│ ┌───────────────────┐ ┌────────────────────┐ │
│ │ Budget left       │ │ Spent in October   │ │
│ │ Rs 156,626        │ │ Rs 78,374          │ │
│ │ of Rs 235,000     │ │ Rs 9,800 less than │ │
│ │ 33% used          │ │ this time in Sep   │ │
│ │ ! Personal over   │ │                    │ │
│ │   by Rs 1,200     │ │                    │ │
│ └───────────────────┘ └────────────────────┘ │
│ ┌──────────────────────────────────────────┐ │
│ │ Until next salary   15 days · Wed 21 Oct │ │
│ │ [██████░░░░░░░░░░░░░░░░░░░░░] 18%        │ │
│ │ Due Rs 87,050     Left after bills       │ │
│ │                   Rs 397,750             │ │
│ │ Due includes the overdue gas bill ·      │ │
│ │ USD at $1 = Rs 280                       │ │
│ └──────────────────────────────────────────┘ │
│ Upcoming · next 7 days              See all ›│
│ ┌──────────────────────────────────────────┐ │
│ │ THU 8  Internet · Nayatel      Rs 6,500  │ │
│ │ SAT 10 Car installment        Rs 45,000  │ │
│ │ MON 12 Netflix                 Rs 1,100  │ │
│ └──────────────────────────────────────────┘ │
│ ┌───────────────────┐ ┌────────────────────┐ │
│ │ Owed to you       │ │ You owe            │ │
│ │ Rs 35,000         │ │ Rs 88,000          │ │
│ │ Usama and Bilal   │ │ Ammi, Office       │ │
│ │ owe you         › │ │ partner, Ali     › │ │
│ └───────────────────┘ └────────────────────┘ │
│ Where it went · Oct   (donut)                │
│  Office 48% · Transport 21% · Food 20% ·     │
│  Personal 8% · Utilities 2% · Subscr. 1%     │
│ Insights · September · net +Rs 328,435     › │
│ Never backed up.        [Back up now]    ✕   │
├──────────────────────────────────────────────┤
│ (Home) Activity Budget Calendar People   (+) │
└──────────────────────────────────────────────┘
```

### 9.2 Add transaction (SCR-05)
```
┌──────────────────────────────────────────────┐
│ Cancel        New expense              Save  │
│                                              │
│            −Rs 14,517   Expense ▾            │
│        from  HBL · PKR ▾   Today ▾           │
│ ┌──────────────────────────────────────────┐ │
│ │ Shell, Gulberg                    📎     │ │
│ └──────────────────────────────────────────┘ │
│  ┌──────┐ ┌─────────┐ ┌──────────┐ ┌──────┐  │
│  │●Fuel │ │Groceries│ │Dining out│ │Office│  │
│  │Transp│ │Food     │ │Food      │ │refr. │  │
│  └──────┘ └─────────┘ └──────────┘ └──────┘  │
│  ┌──────┐ ┌──────────────┐ ┌ ─ ─ ─┐          │
│  │Other │ │All categories…│ │ + Add│         │
│  └──────┘ └──────────────┘ └ ─ ─ ─┘          │
│ ┌──────────────────────────────────────────┐ │
│ │ Split                       Not split  › │ │
│ └──────────────────────────────────────────┘ │
│ ┌────────────┬────────────┬────────────┐     │
│ │     1      │     2      │     3      │     │
│ │     4      │     5      │     6      │     │
│ │     7      │     8      │     9      │     │
│ │    000     │     0      │     ⌫      │     │
│ └────────────┴────────────┴────────────┘     │
│  (USD account: "000" key becomes ".")        │
└──────────────────────────────────────────────┘
Type ▾ menu: Expense ✓ · Income · Transfer (Between your accounts ›)
             · Lend or borrow (With a person) · Settle up (Pay back or get paid)

Lend or borrow layout replaces category chips:
│ Person          Usama ▾     │ Direction   I lent ▾          │
│ Due date (optional)  None ▾ │ Follow-up reminder   Off ▾    │
│ Not counted as spending. It shows on Usama's page in People.│
```

### 9.3 Split expense (SCR-07)
```
┌──────────────────────────────────────────────┐
│ ‹ Add            Split                 Done  │
│ Total amount                                 │
│ Rs 3,200                                     │
│ Office tea & snacks · Office refreshments ·  │
│ Today                                        │
│ ┌──────────────────────────────────────────┐ │
│ │ With                       Office ▾      │ │
│ └──────────────────────────────────────────┘ │
│ WHO PAID, AND HOW TO SPLIT                   │
│ ┌──────────────────────────────────────────┐ │
│ │ ◉ You paid, split equally                │ │
│ │   Office partner owes you Rs 1,600       │ │
│ │ ○ You are owed the full amount           │ │
│ │   Office partner owes you Rs 3,200       │ │
│ │ ○ Office partner paid, split equally     │ │
│ │   You owe Office partner Rs 1,600        │ │
│ │ ○ Office partner is owed the full amount │ │
│ │   You owe Office partner Rs 3,200        │ │
│ │ ○ More options                         › │ │
│ │   Unequal amounts, %, shares, someone    │ │
│ │   from your list or several payers       │ │
│ └──────────────────────────────────────────┘ │
│ ✓ Rs 0 left to assign                        │
│ Your share                         Rs 1,600  │
│ Only your share counts toward your budget.   │
└──────────────────────────────────────────────┘
More options expands:
│ Paid by        You · Cash ▾  │ Split        Equally ▾        │
│ MEMBERS                                     equal share     │
│ [✓] Y  You                                   Rs 1,600       │
│ [✓] O  Office partner                        Rs 1,600       │

With ▾ picker (sheet):
┌──────────────────────────────────────────────┐
│ Cancel          Split with             Done  │
│ [ Type a name or group                    ]  │
│ GROUPS                                       │
│  Office · you and Office partner          ✓  │
│  Hunza trip · you, Ali, Sara, Bilal          │
│  Home groceries · you and Ammi               │
│ PEOPLE · PICK ONE OR MORE                    │
│  U Usama        owes you Rs 25,000           │
│  B Bilal        owes you Rs 10,000           │
│  A Ali          you owe Rs 3,200             │
│ (typed "Hamza") No one called "Hamza" yet.   │
│  (+) Add "Hamza" as a new person             │
└──────────────────────────────────────────────┘
```

### 9.4 Activity (SCR-08)
```
┌──────────────────────────────────────────────┐
│ Activity                          (filter ²) │
│ ┌──────────────────────────────────────────┐ │
│ │ ⌕ [Shared ×] [HBL ×] Search payee, note… │ │
│ └──────────────────────────────────────────┘ │
│ TODAY · TUE 6 OCT              Rs 16,117 spent│
│ ┌──────────────────────────────────────────┐ │
│ │ Office tea & snacks          −Rs 3,200 … │ │
│ │ Office group · you paid ·  your share    │ │
│ │ equally · Cash               Rs 1,600    │ │
│ │ Lent to Usama               −Rs 20,000 … │ │
│ │ Loan · Easypaisa             not spending│ │
│ │ Shell, Gulberg              −Rs 14,517 … │ │
│ │ Fuel · HBL                               │ │
│ └──────────────────────────────────────────┘ │
│ YESTERDAY · MON 5 OCT          Rs 19,690 spent│
│ ┌──────────────────────────────────────────┐ │
│ │ Kababjees                    −Rs 4,350 … │ │
│ │ Office reimbursement          +$250.00 … │ │
│ │ Office group · your income Rs 35,000     │ │
│ │ Imtiaz Super Market          −Rs 8,940 … │ │
│ │ Wise → HBL            $500 → Rs 139,350  │ │
│ │ Transfer                 rate 278.70     │ │
│ │ Office electricity  No account movement… │ │
│ │ Office partner paid   your share Rs 6,400│ │
│ └──────────────────────────────────────────┘ │
│ Day totals are your share of spending.       │
│ Transfers and loans are not spending.        │
│ USD at $1 = Rs 280.                          │
├──────────────────────────────────────────────┤
│ Home (Activity) Budget Calendar People   (+) │
└──────────────────────────────────────────────┘
Filter menu: SHOW ONLY Expense · Income · Transfer · Shared · Loans
             By account ›  By category ›  [Clear all filters]
Row "…": Edit · Split · Change category · Repeat · Delete · Cancel
```

### 9.5 Transaction detail (SCR-09)
```
┌──────────────────────────────────────────────┐
│ ‹ Activity                 (repeat)(del) Edit│
│          Office tea & snacks                 │
│              −Rs 3,200                       │
│   Expense · Tue 6 Oct 2026 · from Cash       │
│          your share Rs 1,600                 │
│ DETAILS                                      │
│ ┌──────────────────────────────────────────┐ │
│ │ Type          Expense                    │ │
│ │ Account       Cash · Rs 26,000           │ │
│ │ Category      Office › Office refreshm.  │ │
│ │ Payee         Office tea & snacks        │ │
│ │ Date          Tue 6 Oct 2026             │ │
│ │ Tags          #office                    │ │
│ └──────────────────────────────────────────┘ │
│ SPLIT                                        │
│ ┌──────────────────────────────────────────┐ │
│ │ Office group · paid by you · equally   › │ │
│ │ Y You                         Rs 1,600   │ │
│ │ O Office partner              Rs 1,600   │ │
│ └──────────────────────────────────────────┘ │
│ Only your share counts as spending.          │
│ RECEIPT                                      │
│ ┌──────┐ Read on device                      │
│ │ img  │ Total Rs 3,200 ✓ matches            │
│ └──────┘ Date 6 Oct ✓ matches                │
│ LINKED                                       │
│ │ Office group     you owe Rs 9,800      › │ │
│ │ Office budget    Rs 38,000 of 75,000   › │ │
└──────────────────────────────────────────────┘
```

### 9.6 Budget (SCR-11)
```
┌──────────────────────────────────────────────┐
│ Budget                         (chart)  Edit │
│ October 2026 ▾                               │
│ ┌──────────────────────────────────────────┐ │
│ │   ◯ 33%     Left this month              │ │
│ │   used      Rs 156,626                   │ │
│ │             Spent Rs 78,374 of           │ │
│ │             Rs 235,000 · 33% used        │ │
│ │             Calendar month · 1–31 Oct    │ │
│ │ ! Personal is over budget by Rs 1,200  › │ │
│ └──────────────────────────────────────────┘ │
│ CATEGORIES · your shares                     │
│ ┌──────────────────────────────────────────┐ │
│ │ Rs 3,000 unassigned            [Assign]  │ │
│ │ Limits add up to Rs 232,000 of 235,000   │ │
│ ├──────────────────────────────────────────┤ │
│ │ Office (my share)  Rs 38,000 / 75,000  › │ │
│ │ ███████████░░░░░░░░░ staff share due 25  │ │
│ │ Transport          Rs 16,367 / 75,000  › │ │
│ │ Food               Rs 15,470 / 30,000  › │ │
│ │ Financial          Rs 0 / 20,000       › │ │
│ │ Subscriptions      Rs 837 / 15,000     › │ │
│ │ Utilities          Rs 1,500 / 12,000   › │ │
│ │ Personal  ! over   Rs 6,200 / 5,000    › │ │
│ └──────────────────────────────────────────┘ │
│ GROUPS · whole-group spend                   │
│ │ Office group     Rs 76,000 of 150,000  › │ │
│ Reports · Budget kept 5 of 6 months      ›   │
│ Your shares only · transfers and loans       │
│ excluded · USD at $1 = Rs 280 · warn at 80%  │
├──────────────────────────────────────────────┤
│ Home Activity (Budget) Calendar People   (+) │
└──────────────────────────────────────────────┘
```

### 9.7 Calendar (SCR-14)
```
┌──────────────────────────────────────────────┐
│ [Today]            (list) (view ▾)    (+)    │
│ 2026                                         │
│ October                              ‹   ›   │
│ ┌──────────────────────────────────────────┐ │
│ │ Due before salary · Wed 21 Oct · 15 days │ │
│ │ Rs 87,050   ! Includes overdue Gas 3,250 │ │
│ └──────────────────────────────────────────┘ │
│  M     T     W     T     F     S     S       │
│                    1✓■   2✓    3✓●   4       │
│  5!■   6●    7     8■    9     10◆   11      │
│  12●   13    14    15◆   16    17    18●     │
│  19    20●   21▲   22    23    24●   25■     │
│  26    27●   28    29    30    31○3          │
│ ■ Bill ● Subscription ◆ Plan ▲ Income        │
│ ○ People ✓ Paid ! Overdue  2 items that day  │
│ TUESDAY 6 OCTOBER                            │
│ ┌──────────────────────────────────────────┐ │
│ │ Nothing due today. Next: Internet ·      │ │
│ │ Nayatel, Thu 8 Oct.                      │ │
│ └──────────────────────────────────────────┘ │
│ (day 5 selected)                             │
│ │ ! Gas bill · SNGPL   Rs 3,250  Overdue ⇆│ │
│ │ ✓ Office electricity Rs 12,800  Paid     │ │
│ Tap a row to open it. Use ⇆ (or swipe) for  │
│ Paid and Skip. USD at $1 = Rs 280.           │
├──────────────────────────────────────────────┤
│ Home Activity Budget (Calendar) People   (+) │
└──────────────────────────────────────────────┘
(list) → Bills & subscriptions (push) · (view ▾) Month ✓ / Agenda list
(+) → New reminder: Title · Amount (optional) · Date · Repeat ▾ · Remind me ▾
```

### 9.8 Bills & subscriptions with Kameti and Car installment (SCR-17)
```
┌──────────────────────────────────────────────┐
│ ‹ Calendar                               (+) │
│ Bills & subscriptions                        │
│ ┌──────────────────────────────────────────┐ │
│ │ Every month          Every year          │ │
│ │ Rs 161,715           Rs 1,940,580        │ │
│ │ [Office███████|Plans██████|Sub█|Bills█]  │ │
│ │ Your shares only · gas and electricity   │ │
│ │ are estimates · USD at $1 = Rs 280       │ │
│ └──────────────────────────────────────────┘ │
│ DUE NOW                                      │
│ │ ! Gas bill · SNGPL  Rs 3,250  [Mark paid]│ │
│ │   Was due Mon 5 Oct · estimated          │ │
│ UPCOMING                          Oct – Nov  │
│ │ Internet · Nayatel  Thu 8 Oct   Rs 6,500 │ │
│ │ Netflix · Mon 12 Oct · HBL card Rs 1,100 │ │
│ │ ChatGPT Plus · Sun 18 Oct   $20.00     › │ │
│ │                             ≈ Rs 5,600   │ │
│ Due before salary (Wed 21 Oct): Rs 83,800,  │
│ plus overdue Gas Rs 3,250 = Rs 87,050.       │
│ PLANS                               2 active │
│ ┌──────────────────────────────────────────┐ │
│ │ ◆ Kameti   Rs 20,000 / month · 12 months │ │
│ │   Jun 2026 → May 2027                    │ │
│ │   ✓ ✓ ✓ ✓ 5 · · · · · · ·                │ │
│ │   J J A S O N D J F M A M                │ │
│ │   Contributed Rs 80,000 of Rs 240,000    │ │
│ │   Next · #5  Thu 15 Oct · Rs 20,000      │ │
│ │   Payout · Dec 2026  Rs 150,000 expected │ │
│ │   Payout · Jun 2027  Rs 150,000          │ │
│ │   ! Payouts (Rs 300,000) don't match     │ │
│ │     contributions (Rs 240,000). Check    │ │
│ │     figures with the committee.          │ │
│ │   [ Pay contribution #5 · Rs 20,000 ]    │ │
│ ├──────────────────────────────────────────┤ │
│ │ ◆ Car installment  Meezan                │ │
│ │   Rs 45,000 / month · 36 months          │ │
│ │   14 of 36 paid          Ends Jul 2028   │ │
│ │   [██████████░░░░░░░░░░░░░░]             │ │
│ │   Remaining Rs 990,000 (22 left)         │ │
│ │   Next due Sat 10 Oct (#15)              │ │
│ │   Schedule · 36 installments           ▾ │ │
│ │   [ Pay installment #15 · Rs 45,000 ]    │ │
│ └──────────────────────────────────────────┘ │
│ SUBSCRIPTIONS   6 active · Rs 14,065 / mo    │
│ OFFICE GROUP BILLS  with Office partner    › │
│ INCOME   Salary $1,875 · 21st · Wise         │
│          Office reimbursement · varies       │
│ PAUSED / CANCELLED                           │
│ │ Amazon Prime Video · Cancelled Aug 2026  │ │
│ │                          [Set up again…] │ │
└──────────────────────────────────────────────┘
```

### 9.9 People (SCR-20)
```
┌──────────────────────────────────────────────┐
│ [▦ Groups · 3]                           (+) │
│ People                                       │
│ ┌───────────────────┐ ┌────────────────────┐ │
│ │ Owed to you       │ │ You owe            │ │
│ │ Rs 35,000         │ │ Rs 88,000          │ │
│ └───────────────────┘ └────────────────────┘ │
│ [ Add shared expense ]                       │
│ ┌──────────────────────────────────────────┐ │
│ │ U Usama   Loans · follow-up 31 Oct       │ │
│ │           owes you  Rs 25,000          › │ │
│ │ B Bilal   Loan · due 31 Oct              │ │
│ │           owes you  Rs 10,000          › │ │
│ │ A Ammi    Loan · no due date             │ │
│ │           you owe   Rs 75,000          › │ │
│ │ O Office partner  Office group           │ │
│ │           you owe   Rs 9,800           › │ │
│ │ A Ali     Hunza trip                     │ │
│ │           you owe   Rs 3,200           › │ │
│ │ S Sara    Hunza trip   ✓ settled       › │ │
│ └──────────────────────────────────────────┘ │
│ Each person shows one balance from loans and │
│ shared groups. Only your share of a split    │
│ counts as your spending.                     │
├──────────────────────────────────────────────┤
│ Home Activity Budget Calendar (People)   (+) │
└──────────────────────────────────────────────┘
After tapping [Groups · 3] (label becomes "Hide groups"):
│ GROUPS                                                   │
│  Office · You and Office partner · equally               │
│                           you owe Rs 9,800             › │
│  Hunza trip · You, Ali, Sara, Bilal · Aug 2026           │
│                           you owe Rs 3,200             › │
│  Home groceries · You and Ammi       ✓ settled         › │
(+) menu: New group · Add person · Add existing balances · Add shared expense
```

### 9.10 Person · Usama (SCR-21)
```
┌──────────────────────────────────────────────┐
│ ‹ People                                (…)  │
│                    ( U )                     │
│                    Usama                     │
│             owes you  Rs 25,000              │
│         Loans Rs 25,000 · shared Rs 0        │
│ ┌──────────────────────────────────────────┐ │
│ │ [Record repayment]  [Lend more / Borrow] │ │
│ │ [Settle up]         [Remind]             │ │
│ └──────────────────────────────────────────┘ │
│ ┌──────────────────────────────────────────┐ │
│ │ Follow-up reminder        Sat 31 Oct ▾   │ │
│ │ Due date                  None ▾         │ │
│ │ Interest (optional)       Off ▾          │ │
│ └──────────────────────────────────────────┘ │
│ The reminder notifies you. Use Remind to     │
│ message Usama.                               │
│ HISTORY                                      │
│ ┌──────────────────────────────────────────┐ │
│ │ Lent · Today · Easypaisa · via Ask UZee  │ │
│ │                            Rs 20,000   › │ │
│ │ Repaid to you · 20 Sep · Easypaisa       │ │
│ │                             Rs 5,000   › │ │
│ │ Lent · 2 Sep · Cash        Rs 10,000   › │ │
│ └──────────────────────────────────────────┘ │
│ Loans and shared expenses with Usama add up  │
│ into this one balance.                       │
└──────────────────────────────────────────────┘
(…) menu: Add shared expense · Write off balance…
Record repayment sheet:
│ Cancel   Record repayment              Save  │
│ Usama paid you back                          │
│ [Rs 5,000] [Rs 10,000] [Full] [Custom]       │
│ Into          Easypaisa ▾  │ Date   Today ▾  │
│ New balance: Usama owes you Rs 20,000        │
│ [            Save repayment              ]   │
```

### 9.11 Group · Office (SCR-22)
```
┌──────────────────────────────────────────────┐
│ ‹ People                                 (+) │
│ Office                    October 2026 ▾     │
│ BALANCE NOW · 2 members · split equally      │
│ ┌──────────────────────────────────────────┐ │
│ │ Y You             you owe   Rs 9,800     │ │
│ │ O Office partner  is owed   Rs 9,800     │ │
│ │ [Remind]                   [Settle up]   │ │
│ └──────────────────────────────────────────┘ │
│ ┌──────────────────────────────────────────┐ │
│ │ Group spend · October    Rs 76,000       │ │
│ │ Your share               Rs 38,000       │ │
│ │ Group budget · Rs 76,000 of Rs 150,000   │ │
│ └──────────────────────────────────────────┘ │
│ ACTIVITY                                     │
│ ┌──────────────────────────────────────────┐ │
│ │ Office tea & snacks · Tue 6 Oct · Cash   │ │
│ │ You paid Rs 3,200   partner owes Rs 1,600│ │
│ │ Office reimbursement · Mon 5 Oct · Wise  │ │
│ │ You received $250.00 ≈ Rs 70,000         │ │
│ │                     you owe Rs 35,000    │ │
│ │ Office electricity · Mon 5 Oct           │ │
│ │ Office partner paid Rs 12,800            │ │
│ │                     you owe Rs 6,400     │ │
│ │ Office rent · Thu 1 Oct · HBL            │ │
│ │ You paid Rs 60,000  partner owes 30,000  │ │
│ └──────────────────────────────────────────┘ │
│ UPCOMING                                     │
│ │ SUN 25 Office staff salaries  Rs 70,000  │ │
│ │        you pay · your share Rs 35,000    │ │
│ │ SAT 31 Settle up by 31 Oct               │ │
│ USD at $1 = Rs 280                           │
└──────────────────────────────────────────────┘
Settle up sheet:
│ Cancel      Settle up                  Save  │
│        Y → O   You pay Office partner        │
│ Amount  Rs 9,800                             │
│ From    HBL ▾          Date  Today ▾         │
│ Settles the full balance. Partial is fine.   │
│ [           Save settlement              ]   │
```

### 9.12 Ask UZee (SCR-03)
```
┌──────────────────────────────────────────────┐
│ ✕                 Ask UZee                   │
│                                              │
│              ┌──────────────────────────────┐│
│              │ I sent 20k to a friend,      ││
│              │ they'll return it later      ││
│              └──────────────────────────────┘│
│ ┌───────────────────────────┐                │
│ │ Who did you lend it to?   │                │
│ └───────────────────────────┘                │
│                                ┌───────────┐ │
│                                │ Usama     │ │
│                                └───────────┘ │
│ ┌──────────────────────────────────────────┐ │
│ │ Usama already owes you Rs 5,000. Add     │ │
│ │ Rs 20,000? New balance Rs 25,000.        │ │
│ │ When should I remind you?                │ │
│ └──────────────────────────────────────────┘ │
│ ┌──────────────────────────────────────────┐ │
│ │ U  New loan · check and save             │ │
│ │ Lend          Rs 20,000 ▾                │ │
│ │ To            Usama ▾                    │ │
│ │ From          Easypaisa ▾                │ │
│ │ Date          Today ▾                    │ │
│ │ Remind        Sat 31 Oct · 10:00 ▾       │ │
│ │ New balance   Usama owes you Rs 25,000   │ │
│ │ [Edit]                         [Save]    │ │
│ └──────────────────────────────────────────┘ │
│ [End of the month] [No reminder]             │
│ ┌────────────────────────────────────┐ (mic) │
│ │ Type a message                   ↑ │       │
│ └────────────────────────────────────┘       │
│ Tap the mic or type · on-device              │
└──────────────────────────────────────────────┘
States: idle (suggestions "What's my next payment?",
"I sent 20k to a friend") · Listening… · Thinking… · answered.
Answer example: "First, one bill is overdue: Gas · SNGPL since
Mon 5 Oct · estimated Rs 3,250. Next is your Internet · Nayatel
bill, Rs 6,500, due Thu 8 Oct." [Pay gas bill] [Open Calendar]
```

### 9.13 Settings (SCR-04)
```
┌──────────────────────────────────────────────┐
│ ‹ Home                                       │
│ Settings                                     │
│ ┌──────────────────────────────────────────┐ │
│ │ (iT) iTech                               │ │
│ │ 9 accounts · data on this iPhone only    │ │
│ └──────────────────────────────────────────┘ │
│ PRIVACY & SECURITY                           │
│ │ Lock with Face ID                  [off] │ │
│ │ Require Face ID          Immediately ▾   │ │
│ │ Hide amounts in app switcher       [on]  │ │
│ │ Hide amounts in notifications      [off] │ │
│ MONEY                                        │
│ │ Accounts                            9  › │ │
│ │ Currency & rate     PKR · $1 = Rs 280 ▾  │ │
│ │ Budget period        Calendar month ▾    │ │
│ │ Salary day           21st ▾              │ │
│ │ Budget warning at    80% used ▾          │ │
│ │ People & groups   6 people · 3 groups  › │ │
│ │ Categories & tags   11 categories      › │ │
│ REMINDERS & SIRI                             │
│ │ Default reminder  1 day before 10:00 ▾   │ │
│ │ Add dues to iPhone Calendar        [off] │ │
│ │ Siri & voice          3 shortcuts      › │ │
│ YOUR DATA                                    │
│ │ Back up now        ! Never backed up   › │ │
│ │ Restore from backup                    › │ │
│ │ Export PDF or CSV                      › │ │
│ │ Import bank statement PDF              › │ │
│ │ Recently Deleted        3 items        › │ │
│ SAMPLE DATA                                  │
│ │ Explore with sample data                 │ │
│ │ Remove sample data (red)                 │ │
│ │ Replay onboarding                      › │ │
│ UZee 1.0 · everything stays on this iPhone   │
└──────────────────────────────────────────────┘
```

### 9.14 Onboarding step 3 · Your accounts (SCR-01)
```
┌──────────────────────────────────────────────┐
│ ‹ Back              Step 3 of 5   ●●●○○      │
│ Your accounts                                │
│ Turn on the ones you use, set each one's     │
│ currency and today's balance, or add your    │
│ own.                                         │
│ BANKS                                        │
│ ┌──────────────────────────────────────────┐ │
│ │ HBL                               [on]   │ │
│ │   Balance  PKR ▾        182,400          │ │
│ │ Meezan                            [on]   │ │
│ │   Balance  PKR ▾         48,000          │ │
│ └──────────────────────────────────────────┘ │
│ CASH                                         │
│ │ Cash                              [on]   │ │
│ │   Balance  PKR ▾         26,000          │ │
│ WALLETS & CARDS                              │
│ ┌──────────────────────────────────────────┐ │
│ │ Easypaisa   [on]  PKR ▾   21,350         │ │
│ │ SadaPay     [on]  PKR ▾   12,450         │ │
│ │ NayaPay     [on]  PKR ▾    9,800         │ │
│ │ Wise        [on]  USD ▾      520.00      │ │
│ │ Fasset      [on]  USD ▾       95.00      │ │
│ │ RedotPay    [on]  USD ▾       45.00      │ │
│ └──────────────────────────────────────────┘ │
│ [ + Add a bank, wallet or card ]             │
│ ┌──────────────────────────────────────────┐ │
│ │ 9 accounts · total today in PKR          │ │
│ │ Rs 484,800                               │ │
│ │ Rs 300,000 + $660 · $1 = Rs 280          │ │
│ └──────────────────────────────────────────┘ │
│ [               Continue                 ]   │
└──────────────────────────────────────────────┘
```

---

## 10. Requirement coverage check (M items with a screen)

| Area | Requirement IDs | Screens |
|---|---|---|
| Accounts | ACC-01…06 | SCR-01, SCR-30…33 |
| Transactions | TXN-01…07 | SCR-05, 06, 08, 09, 10 |
| Currency | CUR-01…04 | SCR-01, 04, 06, all totals |
| Categories | CAT-01…04 | SCR-05, 39, 09 (tags) |
| Budget | BUD-01…07 | SCR-11, 12, 13, 04 |
| Loans | LOAN-01…08 | SCR-05, 21, 24, 28, 17 (installment) |
| Kameti | KAM-01…04 | SCR-17 (Plans), 16, 14 |
| Recurring | REC-01…08 | SCR-16, 17, 18, 19, 14, 02, 42 |
| Shared | SPL-01…12 | SCR-07, 20, 21, 22, 23, 25, 26 |
| Calendar | CAL-01…06 | SCR-14, 15, 19, 04 |
| Dashboard | DSH-01…07 | SCR-02 |
| Reports | RPT-01…09 | SCR-29, 38 |
| Voice | VOX-01…08 | SCR-03, 40, 42 |
| Import | IMP-01…06 | SCR-34, 01 |
| Attachments | ATT-01…02 | SCR-05, 09 |
| Data | DATA-01…05 | SCR-35, 36, 37, 38, 04 |
| Settings | SET-01…04 | SCR-04, 41 |

Gaps that this document specifies but the mockups do not draw: App lock screen (SCR-41), People search, Activity filters for person/group, tag and date range, Accounts "+" add button, category rename/merge editing, delete person/group/recurring dialogs, and generic load/save error states. They follow the existing patterns and need no new visual language.
