# UZee — Product Requirements Document

| | |
|---|---|
| Version | 0.3 (2026-10-06; design audit applied) |
| Date | 2026-10-05 |
| Status | Draft — awaiting user review |
| Source | docs/DISCOVERY.md (Groups 1–8) |

Requirement IDs are permanent. Changed requirements keep their ID and note the change in the Change Log at the end.

---

## 1. Product overview

UZee is a native iPhone and iPad app for managing personal and shared-office finances in PKR and USD. It combines a ledger (accounts, income, expenses, transfers), a planner (budgets, recurring payments, subscriptions, loans, kameti, forecast) and a reminder calendar, with an English voice assistant that answers money questions and records entries. All data stays on the device in v1, and all AI runs on-device.

## 2. Product objectives

| ID | Objective | Measure |
|----|-----------|---------|
| OBJ-1 | Always know how much money is available and how much budget is left this month | Dashboard shows both within 1 second of opening |
| OBJ-2 | Never miss a bill, subscription, installment, kameti or repayment | Every dated obligation produces a calendar entry and a reminder |
| OBJ-3 | Record an expense in under 10 seconds | Manual entry ≤ 4 taps after amount; voice entry in one sentence + confirm |
| OBJ-4 | Clear picture of who owes whom (people, office partner) | Owed/owing totals per person always current |
| OBJ-5 | Financial numbers are always correct | Zero calculation defects in release; all money math covered by tests |

## 3. Target users

| Persona | Description |
|---------|-------------|
| Primary: Owner (iTech) | Salaried professional paid in USD via Wise, spends in PKR across many banks and wallets, shares an office and its costs 50/50 with a friend, lends to and borrows from family and friends, pays a car installment and a kameti, has many subscriptions |
| Future: Other individuals | Similar users once the app is stable enough to share (via TestFlight or App Store) |

Other people (family, friends, office partner) are **person records** grouped into groups, not app users, in v1.

## 4. Primary use cases

| ID | Use case |
|----|----------|
| UC-01 | Check available balance, budget left and spending this month |
| UC-02 | Record an expense, income or transfer (manual or voice) |
| UC-03 | Move money between own accounts, including USD → PKR conversion |
| UC-04 | Set a monthly budget and category limits; see utilization and overspending |
| UC-05 | Record money lent to or borrowed from a person; record partial repayments |
| UC-06 | Track the car installment and kameti schedules |
| UC-07 | Track recurring bills and subscriptions; confirm payments when due |
| UC-08 | See all money dates on a month calendar; get reminders |
| UC-09 | Split expenses and income with people or groups (e.g. Office with a partner), see balances, settle up |
| UC-10 | Ask "how much do I owe my mother?" or "what's my next recurring payment?" by voice |
| UC-11 | Import past and monthly bank statements (PDF) |
| UC-12 | View reports and the "until next salary" forecast |
| UC-13 | Back up, restore and export data |

## 5. Functional requirements

Priority: **M** = must have in v1, **S** = should have in v1, **C** = could have (v1 if time allows), **L** = later version.

### 5.1 Accounts (ACC)
| ID | Requirement | P |
|----|-------------|---|
| ACC-01 | Create, edit, archive accounts: name, type, currency (PKR/USD), opening balance, opening date, icon/colour, include-in-totals flag | M |
| ACC-02 | Account types: Cash, Bank, Savings, Credit card, Digital wallet, Multi-currency (e.g. Wise), Crypto/exchange held as fiat (Fasset, RedotPay), Other | M |
| ACC-03 | Balance = opening balance + sum of posted transactions; never stored as an editable number | M |
| ACC-04 | Balance adjustment entry (reconcile to a real-world balance) recorded as a separate, visible transaction | M |
| ACC-05 | Accounts with transactions cannot be hard-deleted; they are archived | M |
| ACC-06 | Pre-filled suggestions on first run: Easypaisa, NayaPay, SadaPay, HBL, Meezan, Wise (USD), Fasset (USD), RedotPay (USD), Cash (PKR) | S |

### 5.2 Transactions (TXN)
| ID | Requirement | P |
|----|-------------|---|
| TXN-01 | Types: Expense, Income, Transfer, Refund, Adjustment | M |
| TXN-02 | Fields: amount, currency (from account), date and time, account, category/subcategory, payee, note, tags, attachments, split (none, person or group, method, payer), status (Posted/Pending) | M |
| TXN-03 | Transfer: from account, to account, amount sent, amount received; if currencies differ, implied rate shown and stored. Transfers are excluded from income/expense totals | M |
| TXN-04 | Edit and delete any transaction; delete moves to Recently Deleted | M |
| TXN-05 | Transaction list: grouped by day, running totals, filter by account, category, tag, type, person/group, date range; search by note, payee, amount | M |
| TXN-06 | Quick add: amount first, then category (recent/frequent first), account defaults to last used | M |
| TXN-07 | Duplicate transaction ("repeat this") | S |
| TXN-08 | Split a single transaction across categories | C |

### 5.3 Currency (CUR)
| ID | Requirement | P |
|----|-------------|---|
| CUR-01 | Base currency PKR; supported currencies PKR and USD (more addable later without schema change) | M |
| CUR-02 | Money stored as integer minor units + ISO currency code; no floating point | M |
| CUR-03 | Exchange rate table editable in Settings; v1 default 1 USD = 280 PKR | M |
| CUR-04 | Totals in PKR convert USD at the current table rate; transfers keep their actual rate for history | M |
| CUR-05 | Live rates (e.g. Wise) | L |

### 5.4 Categories, payees, tags (CAT)
| ID | Requirement | P |
|----|-------------|---|
| CAT-01 | Two-level category tree (category → subcategory), separate trees for expense and income, editable, with icon and colour | M |
| CAT-02 | Default tree provided (Appendix A), user can rename, reorder, hide, merge | M |
| CAT-03 | Payees (shops, people, companies) saved and suggested; payee remembers last category | S |
| CAT-04 | Free-form tags, multiple per transaction, filterable | M |

### 5.5 Budgeting (BUD)
| ID | Requirement | P |
|----|-------------|---|
| BUD-01 | Monthly budget per calendar month with a total limit; optional setting to run budgets by salary cycle instead (e.g. 21st to 20th). Calendar month is the default | M |
| BUD-02 | Optional limits per category (and subcategory) | M |
| BUD-03 | Utilization = posted expenses in the month (PKR, converted) ÷ limit; remaining = limit − spent | M |
| BUD-04 | Warning at configurable threshold (default 80%) and alert when exceeded | M |
| BUD-05 | New month copies previous month's limits automatically; limits reset (no rollover) | M |
| BUD-06 | Budget history per month and per category | M |
| BUD-07 | Budgets count only my share of split expenses; optional budget per group (e.g. Office) | S |
| BUD-08 | Optional rollover of unspent budget | L |

### 5.6 People, loans and debts (LOAN)
| ID | Requirement | P |
|----|-------------|---|
| LOAN-01 | People records: name, optional phone/notes; one person can have both lent and borrowed records | M |
| LOAN-02 | Loan record: direction (I owe / owed to me), person or institution, original amount, currency, date, due date (optional), interest (optional, simple rate), notes, status (Open, Partially paid, Settled, Written off) | M |
| LOAN-03 | Repayments: partial or full, each linked to an account transaction; remaining balance computed | M |
| LOAN-04 | Per-person net position: total I owe them, total they owe me, net | M |
| LOAN-05 | Lending money from an account creates the account transaction and the loan together | M |
| LOAN-06 | Installment loan (e.g. car): schedule of N installments with amount and due day; each paid installment linked to a transaction | M |
| LOAN-07 | Reminders: before my due dates, and follow-up reminders for money owed to me | M |
| LOAN-08 | Fast entry of many existing loans (opening balances without history) | M |

### 5.7 Kameti (KAM)
| ID | Requirement | P |
|----|-------------|---|
| KAM-01 | Kameti record: name, monthly contribution, currency, start month, duration (months), one or more payout dates and amounts | M |
| KAM-02 | Contribution schedule generates calendar entries and reminders | M |
| KAM-03 | Recording a contribution or payout creates linked transactions | M |
| KAM-04 | Shows contributed so far, remaining contributions, payouts received/expected | M |

Example (user's kameti, figures to confirm): 20,000 PKR/month for 12 months from June 2026; payouts 150,000 PKR in Dec 2026 and 150,000 PKR in Jun 2027.

### 5.8 Recurring payments and subscriptions (REC)
| ID | Requirement | P |
|----|-------------|---|
| REC-01 | Recurring item: name, type (Bill, Rent, Utility, Salary payout, Insurance, Membership, Subscription, Income, Other), amount (fixed or estimated), currency, account, category, optional split (person or group), frequency (weekly, monthly, quarterly, yearly, custom N days/months), next due date, end date (optional) | M |
| REC-02 | On the due date the item appears as "Due" and a reminder fires; user confirms (optionally editing amount) to post the transaction, or skips | M |
| REC-03 | Subscriptions additionally track service, renewal date, cancellation status (Active, Cancelled, Paused), price history | M |
| REC-04 | Monthly and yearly subscription cost totals | M |
| REC-05 | Recurring income: salary $1,875 to Wise around the 21st; variable reimbursements | M |
| REC-06 | Auto-post option per item | L |
| REC-07 | One Bills & subscriptions hub lists all recurring items, the kameti and installment plans (KAM, LOAN-06) with their progress, income items, and paused/cancelled items, with monthly and yearly totals. Kameti and car installment have no separate screens | M |
| REC-08 | Every due item can be marked Paid (amount editable), Skipped or Snoozed from the hub, Calendar, Home and the notification | M |

### 5.9 Shared expenses and groups (SPL), Splitwise-style
Replaces the earlier office-only split (OFF-01…06, withdrawn 2026-10-06). The office is now just one group.

| ID | Requirement | P |
|----|-------------|---|
| SPL-01 | People (shared with Loans): one record per person; a person's balance combines loans and shared expenses | M |
| SPL-02 | Groups: name, icon, members (me + people), default split method, optional currency; e.g. "Office", "Trip to Hunza", "Home" | M |
| SPL-03 | Any expense can be split: with one person or a group; "Paid by" me, another member, or several payers with amounts | M |
| SPL-04 | Split methods: equally (choose who is included), exact amounts, percentages, shares (e.g. 2:1); totals must match the expense before saving | M |
| SPL-05 | Only my share counts as my spending in budgets and reports; the rest becomes money owed to me (or by me) | M |
| SPL-06 | Expenses someone else paid are recorded without touching my accounts; my share is still spending, and I owe the payer | M |
| SPL-07 | Balances: per person, per group, and overall "You are owed / You owe", always computed, never typed | M |
| SPL-08 | Settle up: record a payment between me and a person (full or partial, any account); balance updates | M |
| SPL-09 | Simplify debts within a group (fewest payments to settle everyone) | S |
| SPL-10 | Shared income (e.g. office reimbursement) can be split the same way; my share is my income | M |
| SPL-11 | Settle-up reminders per person or group (e.g. month-end for Office) | M |
| SPL-12 | Group activity feed and group totals by month | S |
| SPL-13 | Friends using their own UZee/Splitwise to see balances | L |

### 5.10 Calendar and reminders (CAL)
| ID | Requirement | P |
|----|-------------|---|
| CAL-01 | Month calendar showing dots/badges for salary, bills, subscriptions, installments, kameti, loan due dates, follow-ups and custom events | M |
| CAL-02 | Tap a day: list of items with amount and status (Due, Paid, Overdue, Upcoming) | M |
| CAL-03 | Custom events and reminders, including non-money ones, with optional repeat | M |
| CAL-04 | Reminder lead time (same day, N days before) and time of day: global default in Settings, overridable per item | M |
| CAL-05 | One reminder per occurrence; overdue items highlighted in app (no repeat nagging in v1) | M |
| CAL-06 | Optional write of UZee events to an iOS calendar chosen by the user; changes and deletions in UZee update it | M |
| CAL-07 | Works correctly across month ends, year ends, leap years, time zone and device clock changes | M |
| CAL-08 | Repeat reminders until paid | L |

### 5.11 Dashboard (DSH)
| ID | Requirement | P |
|----|-------------|---|
| DSH-01 | Top cards: Available balance (sum of included accounts, PKR), Budget left this month, Spent this month | M |
| DSH-02 | Upcoming (next 7 days) payments and income | M |
| DSH-03 | Owed to me / I owe totals | M |
| DSH-04 | "Until next salary" forecast: available balance − unpaid bills, subscriptions, installments and kameti due before the next expected salary date | M |
| DSH-05 | Spending by category donut for the current month | M |
| DSH-06 | Shared card: overall owed/owing across people and groups, top groups | M |
| DSH-07 | Alerts: over budget, overdue items, large unexpected spend | S |

### 5.12 Reports (RPT)
| ID | Requirement | P |
|----|-------------|---|
| RPT-01 | Spending by category (donut), any month or range | M |
| RPT-02 | Income vs expenses by month (bar) | M |
| RPT-03 | Budget performance by month and category | M |
| RPT-04 | Subscriptions and recurring cost (monthly and yearly) | M |
| RPT-05 | Owed/owing summary per person | M |
| RPT-06 | Group and person balance report (monthly, e.g. Office settlement) | M |
| RPT-07 | Account balances over time and net position | S |
| RPT-08 | Cash-flow trend (6–12 months) | S |
| RPT-09 | Export any report as PDF | M |

### 5.13 Voice assistant (VOX)
| ID | Requirement | P |
|----|-------------|---|
| VOX-01 | Invocation: "Hey Siri, ask UZee …" (App Shortcuts), in-app mic button, Action Button and Lock Screen/Control Center control | M |
| VOX-02 | Language: English | M |
| VOX-03 | Questions answered from local data, e.g. next recurring payment, total subscriptions this month, how much I owe a person, budget left, spending in a category | M |
| VOX-04 | Create expense, income, transfer, loan (lent/borrowed), repayment, reminder and event from a sentence | M |
| VOX-05 | Asks follow-up questions for missing required fields (e.g. "What is your friend's name?") | M |
| VOX-06 | Matches people, accounts and categories to existing records; offers to create a new person when no match | M |
| VOX-07 | Always shows a confirmation card before saving anything | M |
| VOX-08 | Runs on Apple's on-device model (Foundation Models); no data leaves the device. If unavailable (unsupported device or Apple Intelligence off), voice falls back to fixed Siri commands and the app explains why | M |

Example flow (VOX-04/05/06): "I sent 20k PKR to a friend, they will return it later" → "What's your friend's name?" → "Usama" → finds Usama in People (or offers to create) → confirmation card: Lent 20,000 PKR to Usama from [account] → Save.

### 5.14 Smart features (AI)
| ID | Requirement | P |
|----|-------------|---|
| AI-01 | Suggest category from payee/note (on-device) | S |
| AI-02 | Read amount, date and merchant from a receipt photo (on-device text recognition) | S |
| AI-03 | Monthly insight summary (e.g. "Dining up 30% vs last month") | C |

### 5.15 Statement import (IMP)
| ID | Requirement | P |
|----|-------------|---|
| IMP-01 | Import a bank/wallet statement PDF into a chosen account | M |
| IMP-02 | Review screen before saving: each row editable, category suggested, rows can be excluded | M |
| IMP-03 | Duplicate detection against existing transactions (same account, date, amount) | M |
| IMP-04 | Supports past history and ongoing monthly imports | M |
| IMP-05 | Onboarding recommends importing past statements from all banks for better history and pattern analysis | M |
| IMP-06 | Bank-specific readers built from sample statements supplied by the user; unsupported formats show a clear message | M |
| IMP-07 | CSV import | S |

### 5.16 Attachments (ATT)
| ID | Requirement | P |
|----|-------------|---|
| ATT-01 | Attach photos (camera/library) and PDFs to transactions, loans, recurring items | M |
| ATT-02 | Attachments stored inside the app's protected storage and included in backups | M |

### 5.17 Data management (DATA)
| ID | Requirement | P |
|----|-------------|---|
| DATA-01 | Recently Deleted: deleted records kept 30 days, restorable, then purged | M |
| DATA-02 | Manual encrypted backup file (password-protected) saved via Files/iCloud Drive; restore from such a file | M |
| DATA-03 | CSV export of transactions and other entities | M |
| DATA-04 | Sample data mode, clearly labelled, removable in one action without touching real data | M |
| DATA-05 | Automatic schema migration on app update with a pre-migration safety copy | M |
| DATA-06 | Cloud sync across devices | L |

### 5.18 Settings and security (SET)
| ID | Requirement | P |
|----|-------------|---|
| SET-01 | Optional app lock with Face ID / Touch ID and device passcode fallback; lock timeout setting | M |
| SET-02 | Hide amounts in app switcher snapshot when lock is on | M |
| SET-03 | Reminder defaults, exchange rate, base currency, salary day, budget warning threshold | M |
| SET-04 | Calendar export on/off and target calendar | M |

## 6. Non-functional requirements

| ID | Requirement |
|----|-------------|
| NFR-01 | Fully functional offline (everything except future sync) |
| NFR-02 | Universal app: iPhone (portrait) and iPad (portrait and landscape, split view) |
| NFR-03 | Minimum OS: iOS/iPadOS 26 |
| NFR-04 | Native look and feel; light and dark mode |
| NFR-05 | No third-party analytics, ads or trackers |
| NFR-06 | All money arithmetic is exact (decimal/integer minor units) and covered by automated tests |
| NFR-07 | No crash on launch; crash-free sessions ≥ 99.5% in testing |

## 7. User stories (representative)

| ID | Story | Acceptance |
|----|-------|------------|
| US-01 | As the owner, I want to see available balance, budget left and spent this month when I open the app | Dashboard shows all three, matching account and budget data |
| US-02 | As the owner, I want to add an expense in a few taps | Amount → category → save; account defaults to last used |
| US-03 | As the owner, I want to move $500 from Wise to HBL and record the PKR received | Transfer saved with both amounts; totals unchanged except for rate difference |
| US-04 | As the owner, I want to set Food at 40,000 PKR and be warned at 80% | Warning appears once spending crosses 32,000 |
| US-05 | As the owner, I want to record that I lent Usama 20,000 PKR and later that he returned 5,000 | Usama shows 15,000 owed to me |
| US-06 | As the owner, I want my car installment and kameti on the calendar with reminders | Each due date shows on the calendar and notifies at my chosen time |
| US-07 | As the owner, I want to confirm my Netflix payment when it's due | Due item shows on the day; confirming posts the expense and moves next due date |
| US-08 | As the owner, I want to split an office bill 50/50 with my partner and settle at month end | Office group shows the net balance; Settle up records the payment and zeroes it |
| US-09 | As the owner, I want to ask "how much do I owe my mother?" | Voice answer matches the People screen |
| US-10 | As the owner, I want to import my HBL statement and review it before saving | Rows appear for review; duplicates flagged; nothing saved until I confirm |
| US-11 | As the owner, I want to restore my data on a new phone from a backup file | Restore reproduces all records and attachments |

Full user stories per milestone are written in the Milestone Plan.

## 8. Data requirements

Entities (formal definitions in DATA_MODEL.md, Architecture stage): Account, Transaction, TransferLeg, Category, Payee, Tag, Budget, BudgetLimit, Person, Loan, LoanPayment, InstallmentSchedule, Kameti, KametiEvent, RecurringItem, Subscription details, PriceHistory, FinancialEvent, Reminder, ExchangeRate, Attachment, Group, GroupMember, SplitShare, Settlement, ImportBatch, Settings.

Rules: UUID identifiers; created/updated timestamps on every entity; soft delete with 30-day purge; money as integer minor units + currency; dates stored in UTC with the user's time zone recorded for scheduling; sample data flagged.

## 9. Security requirements
- SEC-01 Data stored in the app sandbox with iOS Data Protection (encrypted when the device is locked).
- SEC-02 Optional biometric/passcode app lock (SET-01).
- SEC-03 Backup files encrypted with a user password; password never stored.
- SEC-04 No financial data in logs, crash reports or notifications' lock-screen text beyond what the user enables (notification preview shows name and amount by default; option to hide amounts).
- SEC-05 No network calls in v1 except none-required; any future network feature must be listed here first.

## 10. Privacy requirements
- PRV-01 All data and AI processing stay on device.
- PRV-02 No accounts, sign-in or server in v1.
- PRV-03 Permissions requested only when the related feature is first used (notifications, calendar, camera, photos, Siri, speech).
- PRV-04 Sample data never mixed with real data.

## 11. Performance requirements
- PRF-01 Cold launch to dashboard ≤ 1.5 s with 10,000 transactions on a supported iPhone.
- PRF-02 Transaction list scrolls smoothly (60 fps) with 10,000 items.
- PRF-03 Reports render ≤ 1 s for a 12-month range.
- PRF-04 Voice answer begins ≤ 3 s after the question ends (on-device model).

## 12. Accessibility requirements
- A11Y-01 Dynamic Type support to the largest accessibility size.
- A11Y-02 VoiceOver labels for all controls and chart summaries.
- A11Y-03 Colour is never the only signal (icons/labels with status colours); WCAG AA contrast.
- A11Y-04 Reduce Motion respected.

## 13. Backup requirements
- Manual encrypted backup and restore (DATA-02) in v1; restore validates the file and shows a summary before replacing data.
- A safety copy is made automatically before restore and before schema migration.
- Automatic/scheduled backup and cloud backup: later, with sync.

## 14. Synchronization requirements
- v1: none (single device).
- Architecture must allow later iCloud (CloudKit) sync without data-model redesign (UUIDs, timestamps, soft deletes, no device-local IDs in relationships).

## 15. Notification requirements
- Local notifications only (no server).
- Sources: recurring items, subscriptions, installments, kameti, loan due dates and follow-ups, budget threshold alerts, custom reminders.
- Lead time and time of day configurable (CAL-04); notifications re-scheduled when items change, time zone changes, or the app is opened after a long gap.
- iOS limits pending local notifications to 64; UZee schedules the nearest ones and refreshes on launch and in background.
- Actions on notification: "Mark paid", "Snooze 1 day", "Open".

## 16. Calendar requirements
- In-app month view is the primary calendar (CAL-01/02).
- Optional export to an iOS calendar via EventKit (CAL-06); UZee owns only the events it created.
- Permission denial leaves in-app calendar fully working.

## 17. Reporting requirements
See RPT-01…09. Reports count my share of split items, currency conversion at current rate (with note), and exclude transfers from income/expense.

## 18. Future extensibility
- New account types, currencies and recurring types added via configuration, not schema change.
- Module boundaries (Accounts, Transactions, Budget, Loans, Recurring, Calendar, Reports, Voice) so new modules plug in.
- Multi-user readiness: every entity owned by a household/owner ID even though v1 has one.

## 19. Known constraints
- iOS does not allow third-party wake words ("Hey Uzee"); voice uses Siri, in-app mic or Action Button.
- On-device AI needs an Apple Intelligence–capable device (iPhone 15 Pro or newer, M-series iPad) and iOS 26+.
- Building requires macOS/Xcode; the user's Mac lacks disk space. Build route pending decision (cloud Mac runners + TestFlight recommended, which needs the paid Apple Developer account).
- Free Apple ID builds expire after 7 days.
- Bank PDF formats differ by bank; each reader needs a real sample.
- Max 64 pending local notifications.

## 20. Assumptions
- AS-01 One user per device; people and group members are records, not users.
- AS-02 Fixed exchange rate is acceptable for totals until live rates are added.
- AS-03 Salary expected on the 21st of each month (user said 21st–22nd).
- AS-04 Kameti amounts will be entered by the user (current figures unconfirmed).
- AS-05 Default reminder: 1 day before at 10:00, editable.
- AS-06 Default budget warning at 80%.

## 21. Out of scope (v1)
- Cloud sync and multi-device
- Multi-user accounts or sharing with the partner's own app
- Live exchange rates
- Direct bank connections/feeds
- Investments, stocks and crypto price valuation
- Mac and web apps
- Languages other than English
- Tax features
- Budget rollover, repeat overdue reminders, auto-posting recurring items

## 22. Future feature candidates

| Feature | What it does | Why it helps | Complexity | Dependencies |
|---------|-------------|--------------|------------|--------------|
| iCloud sync | Same data on iPhone and iPad | Use both devices | High | Paid developer account, CloudKit |
| Live Wise rates | Real USD→PKR rate | Accurate totals | Medium | Network, rate source |
| Shared balances with friends | Friends see group balances in their own app | No manual settling | High | Sync, multi-user |
| Budget rollover | Carry unspent budget | Envelope-style saving | Low | Budget module |
| Repeat reminders until paid | Daily nag for overdue items | Fewer missed payments | Low | Notifications |
| Auto-post recurring items | Post on due date without confirm | Less tapping | Low | Recurring module |
| SMS/notification parsing | Create transactions from bank SMS | Less typing | High | iOS limits; Shortcuts automation |
| Savings goals with targets | Progress to a target amount/date | Motivation | Medium | Accounts |
| Home Screen widgets | Balance/budget at a glance | Faster check | Low | Dashboard |
| Urdu / Roman Urdu voice | Speak naturally in Urdu | Comfort | High | On-device model language support |
| Qibla direction (owner request 2026-10-07) | Compass arrow pointing to the Kaaba from the current location | Daily use, keeps UZee the one personal app | Low | Core Location + heading (magnetometer); location permission |
| Namaz times and reminders (owner request 2026-10-07) | Today's five prayer windows for the current city and country, clearly shown as start and end (e.g. "Fajr · now · ends 5:15 am"), with a notification at each start | Timings change daily; reminders follow location | Medium | Location; an authentic source: either fetch daily timings online (e.g. a recognised timings service) or compute on device with a standard method (University of Islamic Sciences, Karachi; Hanafi Asr) and let the owner pick the method; works offline after fetch; notifications |

---

## Appendix A — Default category tree (proposed)

**Expense**
- Food: Groceries, Dining out, Food delivery, Tea & snacks
- Transport: Fuel, Ride-hailing, Parking & tolls, Car maintenance, Car installment
- Housing: Rent, Maintenance, Furniture
- Utilities: Electricity, Gas, Water, Internet, Mobile
- Subscriptions: Streaming, Software & AI tools, Cloud storage, Apps
- Health: Doctor, Medicine, Lab tests
- Personal: Clothing, Grooming, Gifts
- Family: Family support, Children, Events
- Education: Courses, Books
- Entertainment: Outings, Games, Travel
- Financial: Bank fees, Transfer fees, Loan interest, Kameti contribution
- Office: Office rent, Office utilities, Staff salaries, Office supplies, Office refreshments, Sales commission
- Charity: Zakat, Sadaqah, Donations
- Other

**Income**
- Salary
- Reimbursement: Office expense
- Freelance / Business
- Kameti payout
- Loan received / Repayment received (tracked via Loans)
- Refunds
- Gifts
- Other

## Change log
| Date | Version | Change |
|------|---------|--------|
| 2026-10-05 | 0.1 | First draft from discovery |
| 2026-10-06 | 0.3 | Design audit (docs/design-audit.md) applied: BUD-01 salary-cycle option, REC-07 hub incl. kameti and car installment, REC-08 mark paid everywhere, People is a tab, money actions confirm with Undo, one sample dataset (docs/mockup-dataset.md) |
| 2026-10-06 | 0.2 | Office split (OFF) replaced by Splitwise-style people and groups (SPL); Personal/Office sections removed |
