# UZee — Discovery Kickoff

Stage: **Phase 1 — Requirement Discovery** (no application code is written until the documented stages are complete and approved).

## 1. My understanding of the product

UZee is a personal finance app, iOS first, that gives one place to see and manage where money comes from, where it goes, what is owed in both directions, and what is coming up next. It combines three things that are usually separate apps:

1. **A ledger**: accounts, income, expenses, transfers, with categories, tags, payees and receipts.
2. **A planner**: budgets, savings goals, recurring payments, subscriptions, loan installments and a cash-flow forecast.
3. **A reminder calendar**: every financial date (salary, bills, renewals, repayments, deadlines) on a calendar, with notifications so nothing is missed.

Priorities, in order: data integrity, correct money math, security, reliability, usability, performance, polish, extra features. The architecture must allow new financial modules later without a redesign. Work moves through gated stages (discovery, requirements, prerequisites, PRD, UX, wireframes, approval, architecture, plans, implementation, testing, release) with living documentation and a permanent test and bug-regression registry.

## 2. Major product modules

| # | Module | What it covers |
|---|--------|----------------|
| 1 | Dashboard | Balances, month income/expense, budget usage, upcoming payments, owed/owing, alerts |
| 2 | Accounts | Cash, bank, savings, credit card, wallets, other; balances and transfers |
| 3 | Transactions engine | Income, expenses, transfers, refunds; the single source of truth for money movement |
| 4 | Categories, tags, payees | Classification used by budgets, search and reports |
| 5 | Budgeting | Monthly and category budgets, limits, utilization, overspend alerts, history |
| 6 | Loans and debts | I owe / owed to me, installments, interest, repayment history, status |
| 7 | Recurring payments | Bills, rent, utilities, insurance, memberships, recurring income |
| 8 | Subscriptions | Service, cost, cycle, renewal, cancellation, price history |
| 9 | Savings and goals | Targets, deadlines, contributions, progress |
| 10 | Calendar and reminders | Financial events, custom events, notifications, system calendar link |
| 11 | Reports and forecasting | Income vs expense, by category, trends, net position, cash-flow forecast |
| 12 | Attachments | Receipts and documents linked to records |
| 13 | Data and security | App lock, biometrics, encryption, backup, restore, export, import, sync |
| 14 | Settings | Currency, preferences, notifications, data management, sample data |

## 3. Decisions needed before architecture is finalized

These shape the technology stack and data model, so they come first.

1. **Users**: personal-only vs shared/household (drives auth, sync model, data ownership).
2. **Platforms**: iPhone only, iPhone + iPad, + Mac, future web (drives native SwiftUI vs cross-platform).
3. **Distribution**: personal use on own phone vs App Store release (drives cost, review, privacy labels).
4. **Development machine**: whether a Mac is available (Xcode is required for native iOS).
5. **Sync and backup**: device-only, iCloud (Apple-only, no server), or own backend (needed for web/multi-user).
6. **Currency model**: single base currency vs multi-currency with exchange rates.
7. **Offline expectations**: fully offline-first vs online-required.
8. **Bank connectivity**: manual entry only vs SMS/statement import vs bank feeds (big scope and region factor).
9. **Calendar integration**: in-app calendar only vs writing events to the iOS Calendar.
10. **AI features**: none, or e.g. auto-categorisation, receipt scanning, natural-language entry, insights.
11. **Security level**: app lock/biometrics, encryption at rest, what is acceptable to store in the cloud.

## 4. Phase 1 discovery plan (question groups)

1. **Product scope and platform** (asked now)
2. Money basics: currencies, accounts, income and expense structure, categories, tags
3. Planning: budgets, recurring payments, subscriptions, savings goals
4. Loans, debts and money lent: directions, interest, installments, people
5. Calendar, reminders and notifications
6. Dashboard and reports
7. Data: security, biometrics, backup, sync, export/import, migration from existing tools
8. Extras: attachments, search, AI features, anything else

## 5. Group 1 — Product scope and platform

1. **Users**: Is UZee only for you, or should it support sharing with a partner/family (shared accounts or budgets), now or later?
2. **Platforms**: iPhone only for v1? Do you also want iPad, a Mac app, or a web version later?
3. **Distribution**: Is this for your own use on your phone, or do you plan to publish on the App Store (free or paid)?
4. **Your setup**: Do you have a Mac to develop on (model/macOS version if known), and which iPhone and iOS version will you test on? Do you have a paid Apple Developer account ($99/yr) yet?
5. **Sync**: Should data stay on the phone only, sync through your iCloud across your Apple devices, or live on a server you control?
6. **Today**: How do you track money today (spreadsheet, another app, nothing)? Is there existing data you'll want to import?
7. **Primary purpose**: If UZee could do only three things really well on day one, what would they be?

### Group 1 answers (iTech, 2026-10-05)

| # | Topic | Answer | Decision recorded |
|---|-------|--------|-------------------|
| 1 | Users | Personal/household use now; may share with others later if stable | Single-user v1; keep data model user-scoped so multi-user is possible later |
| 2 | Platforms | iPhone and iPad ("iphone duo" to be clarified) | Native iOS/iPadOS universal app; no Mac or web in scope |
| 3 | Distribution | Own phone for now | No App Store work in v1; free Apple ID signing is enough to start |
| 4 | Setup | Apple M1 Mac available; Apple Developer account later | Development on the M1 Mac with Xcode; paid account listed as REQUIRED LATER |
| 5 | Sync | Phone only for now | Local-first storage; sync deferred, architecture must not block iCloud later |
| 6 | Existing data | Local bank statements as PDF | Bank statement PDF import becomes a requirement to scope in Group 7 |
| 7 | Day-one priorities | 1) Budgeting 2) Notification tracking via calendar events 3) Voice assistant | New module 15: Voice assistant (create events/reminders, answer questions like "how much do I owe my mother", "what do subscriptions cost this month") |

Change management: the voice assistant is a **new module with architectural impact** (Siri / App Intents, speech, possibly on-device or cloud AI). It will be scoped in its own question group before architecture.

Note: Free Apple ID signing installs builds that expire after 7 days; this will be covered in the prerequisites document.

### Group 2 answers (iTech, 2026-10-05)

| # | Topic | Answer | Decision recorded |
|---|-------|--------|-------------------|
| 1 | "iPhone duo" | Apple's new iPhone | Target current iPhone models plus iPad; minimum iOS set in prerequisites |
| 2 | Currency | USD and PKR | Multi-currency from v1: each account has one currency; amounts stored as integer minor units with currency code (no floating point) |
| 3 | Accounts | Easypaisa, NayaPay, SadaPay, HBL, Meezan, Wise, Fasset, RedotPay (and more) | Account types: cash, bank, digital wallet, multi-currency (Wise), crypto/exchange (Fasset, RedotPay) TBC |
| 4 | Income | Fixed salary; office expense of about $250 that varies; received in USD into Wise | Recurring income with expected vs actual amount; USD income account |
| 5 | Categories | Claude proposes categories and subcategories | Default editable category tree to be drafted in the PRD |
| 6 | Tags and payees | Yes | Tags and saved payees in v1 |
| 7 | Transfers | Yes, track transfers so total balance is unchanged; spending is then recorded from the destination account | Transfers are a distinct transaction type excluded from income/expense totals; cross-currency transfers record both amounts (implied rate) |

### Group 3 answers (iTech, 2026-10-05)

| # | Topic | Answer | Decision recorded |
|---|-------|--------|-------------------|
| 1 | Main currency | PKR; fixed 1 USD = 280 PKR for now; live Wise rates later | Base currency PKR; a manually editable rate table (v1: USD→PKR 280); per-transfer actual rate stored; live rates = future feature |
| 2 | Income | Salary $1,875 received around the 21st–22nd each month, plus reimbursements | Recurring income: $1,875 USD into Wise, expected on the 21st; reimbursements are variable income (Reimbursement category) |
| 3 | Fasset / RedotPay | USD balances | Plain USD accounts; no crypto valuation in v1 |
| 4 | Budget style | Whatever is helpful | **Default chosen:** monthly total budget plus optional category limits |
| 5 | Budget period | Calendar month; full calendar showing reminders, recurring payments and subscriptions on their dates | Calendar-month budgets; month calendar view is a core screen |
| 6 | Leftover | Money in an account stays as that account's balance next month | Account balances always carry over; budget limits reset each month (budget rollover = future option) |
| 7 | Bills/subscriptions | Office rent, office utilities, office boy salary, sales agent salary; Apple, Netflix, ChatGPT, Claude and many more | Recurring payments include payroll-type items. **Default chosen:** remind and confirm (no automatic posting) to protect data accuracy |
| 8 | Savings | About 30k currently saved | Currency and goal target to confirm in Group 4 |

### Group 4 answers (iTech, 2026-10-05)

| # | Topic | Answer | Decision recorded |
|---|-------|--------|-------------------|
| 1 | Office vs personal | Not sure yet. The office is shared with a friend: joint spending is split 50/50 at month end; the office then reimburses, and that is split 50/50 too | New requirement: **shared expenses and settlement** (who paid, each person's share, month-end balance with the partner, reimbursement receivable split 50/50). Office separation proposed in Group 5 |
| 2 | Savings | 30k PKR, no target; show as available balance | No savings goal needed now; goals module stays but is lower priority |
| 3 | Money I owe | Many people; will enter after the app is ready | No data migration for loans; fast entry flow matters |
| 4 | Money owed to me | Same as above | Same as above |
| 5 | Installments | Car installment and a monthly kameti | Installment loan type (car); new **Kameti (ROSCA)** type: monthly contribution, payout month, member count |
| 6 | Reminders | Both: before own repayments and follow-ups for money owed to me | Reminders for payables and receivables |

### Group 5 answers (iTech, 2026-10-05)

| # | Topic | Answer | Decision recorded |
|---|-------|--------|-------------------|
| 1 | Office | Yes to the proposal | Separate Office section with its own budget; payer per expense; month-end 50/50 settlement with partner; reimbursement split 50/50 |
| 2 | Kameti | 20k PKR/month for 1 year, started June 2026; payouts 150k PKR in Dec 2026 and 150k PKR in June 2027 | Kameti supports multiple payouts. **Open:** contributions (20k × 12 = 240k) vs payouts (300k) do not match; to confirm |
| 3 | Reminder timing | Configurable in the app, not hard-coded | Per-item lead time and time of day, with a global default in Settings |
| 4 | Overdue repeats | Not for now | Single reminder; overdue items are highlighted in-app; repeat nagging = future candidate |
| 5 | iPhone Calendar | Yes | Optional write of UZee events to iOS Calendar (EventKit), user-selectable calendar |
| 6 | Non-money reminders | Not answered | **Default chosen:** custom reminders/events allowed (master prompt lists custom events) |

### Group 6 answers (iTech, 2026-10-05)

| # | Topic | Answer | Decision recorded |
|---|-------|--------|-------------------|
| 1 | Dashboard | Available balance, budget left this month, total spending this month, etc. | Dashboard leads with these three; upcoming bills and owed/owing below |
| 2 | Reports | Claude decides | **Default chosen (v1):** spending by category (donut), income vs expenses by month, subscriptions and recurring total, owed/owing summary, office monthly settlement, budget performance |
| 3 | Forecast | Yes | "Until next salary" forecast: balance minus bills due before the next expected salary |
| 4 | Presentation | Charts, especially pie/donut by category | Native Swift Charts; donut for category split |

### Group 7 answers (iTech, 2026-10-05)

| # | Topic | Answer | Decision recorded |
|---|-------|--------|-------------------|
| 1 | App lock | Optional Face ID / passcode lock | Off by default; toggle in Settings; device passcode fallback |
| 2 | Backup | Cloud sync will come later | **Default chosen:** v1 includes manual encrypted backup export + restore to Files/iCloud Drive as a data-loss safety net (priority 1 is data integrity); cloud sync stays a later milestone |
| 3 | Bank statement import | Claude decides; app should recommend users import past statements from all their banks for history and pattern analysis | Statement import supports both history and ongoing monthly imports, with review-before-save and duplicate detection; onboarding recommends importing past statements; per-bank PDF parsers built from user-supplied samples (HBL, Meezan, Wise, wallets) |
| 4 | Export | PDF and CSV | CSV data export and PDF report export |
| 5 | Receipts | Yes | Photo/file attachments on transactions |
| 6 | Deletion | Yes | Recently Deleted bin, 30-day retention, restore |

### Group 8 answers (iTech, 2026-10-05)

| # | Topic | Answer | Decision recorded |
|---|-------|--------|-------------------|
| 1 | Language | English | English-only voice and UI in v1 |
| 2 | Invocation | "Hey Uzee, what is my next recurring payment this month and how much?" | **Platform constraint:** iOS does not allow third-party apps to listen for their own wake word. Equivalent: "Hey Siri, ask UZee …" via App Shortcuts/App Intents, plus an in-app mic button, Action Button and Lock Screen/Control Center shortcut |
| 3 | Actions | Also add expenses. Example: "I paid PKR 14,517 for car refuelling"; "I sent 20k PKR to a friend, they will return it later" → UZee asks the friend's name → "Usama" → matches an existing person in owed/owing, else offers to create a new person | Voice can create expenses, loans (lent/borrowed), reminders and events; follow-up questions for missing fields; person matching against existing contacts; always shows a confirmation card before saving |
| 4 | AI engine | Apple AI | Apple Foundation Models (on-device, private, offline). Requires an Apple Intelligence–capable device (iPhone 15 Pro or newer, M-series iPad) and iOS 26+. App falls back to the manual UI where unavailable |
| 5 | Other AI | Yes: auto-categorisation, receipt reading, monthly insights | All on-device: Foundation Models for categorisation and insights, Vision text recognition for receipts |
| 6 | Anything else | Not yet | Discovery closed |

## Discovery status: COMPLETE (2026-10-05)

Open items carried into the PRD:
- **Kameti figures:** 20k × 12 = 240k paid in vs 300k in payouts; unanswered. The kameti model will store each contribution and payout as entered, so the actual figures can be set in the app.
- **Bank statement samples:** one PDF per bank needed before building each import parser.
