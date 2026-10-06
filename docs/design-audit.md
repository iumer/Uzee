# UZee — Design Audit of the iPhone Mockups

| | |
|---|---|
| Date | 2026-10-06 |
| Scope | 11 mockup screens (Home, Add transaction, Activity, Budget, Calendar, Loan · Usama, Subscription · Netflix, Reports, Ask UZee, Settings, Shared) checked against PRD v0.2 and DISCOVERY.md |
| Effort key | S = under a day of design, M = 1–3 days, L = more than 3 days |

## Overall verdict

The mockups look and feel right. The light-mode visual language is calm and Apple-like: large titles, grouped white cards, tabular figures, a glass tab bar and restrained springs. The Home, Budget, Calendar and Shared screens already answer the owner's three priorities at a glance. The set is still a polished brochure, not a usable app design, for three reasons. First, the sample numbers contradict each other across screens: what's due before salary, Usama's balance, the Office balance, October income and "Saved Rs 2.7M". In a finance app that destroys trust (OBJ-5). Second, several core money flows can't be completed. You can't pick an account or date, transfer with a real USD→PKR rate, record who paid a shared bill, lend or borrow manually, or mark a due bill as paid. Third, many controls look tappable but do nothing or go to the wrong screen, which the owner explicitly dislikes. About a dozen screens the PRD marks M are also missing: accounts, the bills and subscriptions list, kameti, onboarding, import review, budget setup, transaction detail, backup and restore, dark mode and iPad. Fix the data and the flows first. Add the missing screens next. Polish comes last.

---

## Must fix

### AUD-01 · Make all sample numbers come from one consistent dataset
**Screens:** Home, Calendar, Shared, Activity, Reports, Settings · **Effort:** S
**Problem:** Figures contradict each other across screens:
- Home "Until next salary" shows Due **Rs 62,600**. Home's own four Upcoming rows already add up to Rs 72,600. Calendar items between 7 and 20 Oct add up to **Rs 83,800**: Internet 6,500, car 45,000, Netflix 1,100, kameti 20,000, and ChatGPT and Claude at $20 each, i.e. Rs 5,600 each at 280. The overdue electricity bill isn't counted either.
- Calendar 28 Oct says Usama "owes you **Rs 20,000**". The Loan, Shared and Voice screens all say **Rs 25,000**: Rs 30,000 lent minus Rs 5,000 repaid.
- The Shared Office balance of +Rs 8,450 ignores two items. Today's "Office tea & snacks, you paid Rs 3,200" in Activity adds +Rs 1,600. Yesterday's "Office reimbursement +$250, your share $125" means you owe the partner $125 (Rs 35,000). The real Office balance is about **−Rs 24,950**, so you owe the partner.
- Calendar shows "Office electricity, Rs 12,800, **Overdue**" on 5 Oct. Shared says "Electricity · K-Electric, **you paid** Rs 12,800".
- Reports shows October income of about Rs 595k on 6 Oct. The salary isn't expected until 21 Oct.
- Reports says "Saved **Rs 2.7M**" over 6 months, but the available balance is Rs 485,200.
- Home shows "+Rs 120,000 this month" under the balance with no definition.
- Settings shows "5 people · 3 groups". Shared plus the split sheet name at least 6 people: Usama, Bilal, Ammi, Partner, Ali and Sara.

**Fix:** Write one seed dataset as a JSON fixture, using the same fixture planned for DATA-04 sample mode. Generate every screen's numbers from it, and add a quick checklist so each total can be traced back to its rows. Define the sub-line under the balance precisely, e.g. "Net +Rs 120,000 since 1 Oct", or drop it.

### AUD-02 · My share of split expenses is missing from Spent and Budget
**Screens:** Home, Budget, Reports, Shared · **Effort:** M
**Problem:** SPL-05 and SPL-06 say my share of shared bills is my spending, including bills the partner paid. In October Shared lists my shares as rent Rs 30,000, salaries Rs 35,000, electricity Rs 6,400 and tea. None of this appears in Home Spent (Rs 115,500), the budget categories or the Reports donut. The Budget script still holds an unused "Office" budget (rent 60,000, staff 45,000…) from the withdrawn OFF design.
**Fix:** Count my share in category spending, for example under "Office" in Appendix A. Show the optional group budget (BUD-07) as a "Groups" section on the Budget screen, not as a tab. Label split rows in Budget drill-downs as "your share of Rs 3,200". Remove the dead Office budget code.

### AUD-03 · Activity rows and day headers don't show what the money did
**Screens:** Activity · **Effort:** S
**Problem:** Day headers read "3 items" instead of a total (TXN-05 asks for running totals). Split rows show the full bill (−Rs 3,200) as the main amount and the share in grey. This mixes "money that left my account" with "my spending". Transfers show "$500.00 → Rs 140,000", exactly 280, which means the actual rate isn't being stored (CUR-04).
**Fix:** Headers should show the day's net spend as my share, in PKR. Each row's main number is the account movement and the secondary line shows "your share Rs 1,600". Transfers show both legs and the implied rate, e.g. "$500 → Rs 139,350 · 278.70". The Wise rate in the sample should differ from 280 so this is visible.

### AUD-04 · Define and apply multi-currency display rules
**Screens:** Home, Activity, Calendar, Subscription, Reports, Voice · **Effort:** M
**Problem:** USD amounts appear with no PKR equivalent: iCloud+ $2.99, ChatGPT $20, Claude $20, salary $1,875 and the $250 reimbursement. The Rs 485,200 available balance hides how much of it is USD held in Wise, Fasset and RedotPay, and it doesn't say which rate was used. The owner thinks in PKR but earns USD.
**Fix:** One rule everywhere. A USD row shows the native amount first, with "≈ Rs 5,600" as a secondary line. Every PKR total that includes USD carries a footnote: "USD at $1 = Rs 280 · edit". The balance card gets a small breakdown, e.g. "Rs 300,000 PKR + $660 USD". Amounts always carry the currency symbol, never a bare "+35,000" as in the Shared Office rows.

### AUD-05 · Add sheet: account, date, payee and decimal entry don't work
**Screens:** Add transaction · **Effort:** M
**Problem:**
- "from HBL · PKR · Today 3:24 PM" is static text, so you can't change the account, currency or date.
- "Note · Shell, Gulberg" is a pre-filled static row.
- Payee, tags, attachment and Pending status (TXN-02) are missing.
- The keypad has no decimal key, so $2.99 or $1,875.50 can't be entered.
- Save navigates away without validating.
- Cancel discards without asking, even after typing.

**Fix:** Make the subtitle line two tappable tokens, account ▾ and date ▾. Account opens a menu of accounts with balances. Date uses the compact date picker. Add a "Payee or note" field with suggestions (CAT-03) and a 📎 receipt button. The decimal key should appear only for USD accounts (PKR keeps "000"). Disable Save until amount and category are set. Show "Discard changes?" when cancelling after edits.

### AUD-06 · Transfer has no From/To accounts or received amount
**Screens:** Add transaction (Transfer) · **Effort:** M
**Problem:** Choosing Transfer only removes the minus sign. There is no destination account, no received amount and no fee. US-03 (move $500 from Wise to HBL and record the PKR received) can't be done, though it's the owner's most frequent monthly move.
**Fix:** Build a dedicated transfer layout with a From card and a To card, each showing account and balance, and a swap button. When currencies differ, show "Sent $500" and "Received Rs ___", the implied rate (e.g. 278.70), and the difference against the 280 table rate. Add an optional fee field that posts as a Financial › Transfer fees expense.

### AUD-07 · Remove top-of-screen segmented controls and chip rows
**Screens:** Add transaction, Activity · **Effort:** S
**Problem:** The owner dislikes segmented switches and tabs at the top of screens. Add has an Expense/Income/Transfer segmented control at the top and a second one for split method. Activity has a horizontal chip row (All, Expense, Income, Transfer, Shared, Loan) that works as tabs.
**Fix:** In Add, show the type as a pull-down token beside the amount ("Expense ▾"). Also offer a long-press menu on the + button: Expense, Income, Transfer, Lend or borrow, Settle up. Split method becomes a row with a menu ("Equally ▾"). In Activity, move filters into a toolbar filter button (line.3.horizontal.decrease). Active filters appear as removable tokens in the search field.

### AUD-08 · Split editor can't record what really happens in the office
**Screens:** Add transaction (Split) · **Effort:** M
**Problem:** "Paid by: You · HBL" is fixed, so "partner paid the rent" (SPL-06) and multiple payers (SPL-03) can't be entered. Exact and % amounts are computed as 60/40 and can't be edited. You can't untick members. There is no "totals must match" check (SPL-04). The keypad disappears when the split panel opens, so the amount can't be changed. The partner is a placeholder named "Partner", not a person record.
**Fix:** Open the split as a pushed page or a large-detent sheet with three parts: a "With" person or group picker, a "Paid by" picker (me, a member, or multiple), and member rows with editable amount, %, or share steppers. Show a live "Rs 0 left to assign" line and disable Done until it reaches zero. Keep the amount editable above it. Use real person names.

### AUD-09 · No manual way to lend, borrow, repay or settle
**Screens:** Add transaction, Shared, Loan, Voice · **Effort:** M
**Problem:** Activity shows "Lent to Usama", which only Voice can create. Add supports just Expense, Income and Transfer, without Refund, Adjustment, loan or settle (TXN-01, LOAN-05). Voice's "Edit" button opens the Add sheet, which can't represent a loan. Fast entry of many existing loans (LOAN-08) has no screen.
**Fix:** Add "Lend or borrow" and "Settle up" entry types, with person, direction, account, date, optional due date and follow-up reminder. Add an "Add existing balances" list for onboarding, with one row per person, amount and direction, and no account movement.

### AUD-10 · Due items can't be marked paid
**Screens:** Calendar, Home Upcoming, Subscription, Loan · **Effort:** M
**Problem:** REC-02 and US-07 (confirm Netflix when due) are core to priority 2, but no screen has a Mark paid, Skip or Edit-amount action. Calendar rows aren't tappable at all. Without this, the "until next salary" forecast and the overdue status can never update.
**Fix:**
- Tapping a due item opens a confirm sheet with the amount editable, account pre-filled, and Pay, Skip this time and Snooze buttons.
- Calendar and Home rows get swipe actions: leading "Paid", trailing "Skip".
- The same three actions appear on notifications (see AUD-29).
- A paid item shows a check icon, not only a green colour.

### AUD-11 · Controls that look tappable but do nothing
**Screens:** All · **Effort:** M
**Problem:** These all look interactive but do nothing:
- Calendar ‹ › month buttons. Budget ‹ › month buttons, where "next" is also greyed out as if disabled.
- Reports "PDF" button, and its Subscriptions and Office settlement tiles.
- Subscription "Pause for a month" and "Mark as cancelled".
- Shared "+" (new group), plus the Hunza trip, Home groceries, Bilal and Ammi rows.
- Voice "Bilal" and "New person" chips.
- Settings rows: Currency & rate, Categories & tags, Default reminder, Back up now, Export, Import bank statement, Recently Deleted.
- Activity search field, which accepts text but never filters.
- Add sheet Note row, Budget category rows, Calendar event rows, Loan history rows, and the Home "9 accounts" text.

**Fix:** Every one either gets a target screen (most are listed under Should add) or is removed from the mockup. Add a review rule: no chevron or tinted text without a destination.

### AUD-12 · Wrong link destinations and dead-end Back buttons
**Screens:** Home, Settings, Budget, Loan, Subscription, Activity · **Effort:** S
**Problem:** Several links go to the wrong place:
- Home "Car installment" opens **Usama's loan**. Kameti and Internet open the whole Calendar.
- Settings › Accounts opens **Activity**.
- Budget "Edit limits" opens **Add transaction**.
- "Edit" on Loan and Subscription opens a blank Add transaction.
- Every Activity row opens a new, pre-filled Add sheet instead of the transaction.
- Loan's back button says "People" and Subscription's says "Subscriptions", but both return to Overview because neither list exists.

**Fix:** Point each to its real destination (AUD-19 to AUD-26). Back labels must name the screen you came from.

### AUD-13 · Money actions save instantly with no confirmation or undo
**Screens:** Loan, Shared · **Effort:** S
**Problem:** On Loan, tapping "Rs 5,000", "Rs 10,000" or "Full" posts a repayment into Easypaisa straight away. The account can't be changed despite the hint, and there's no custom amount. On Shared, "Settle up · partner pays Rs 8,450" posts the full amount into HBL in one tap, with no partial option. The toasts offer no Undo. Mis-taps create wrong ledger entries, which runs against the data-integrity priority.
**Fix:** These buttons should open a small confirm sheet with amount, account and date pre-filled and editable. The toast should say "Repayment saved · Undo" for about 5 s, and the entry also goes to Recently Deleted when undone.

### AUD-14 · Information architecture: People has no tab; Settings, Reports and Subscriptions are buried
**Screens:** Tab bar, Home, Settings · **Effort:** M
**Problem:** Who-owes-whom is a top-five objective (OBJ-4), but Shared/People is reachable only from the two Home owed cards and a Settings row. Reports is reachable only from the donut card. No route reaches a subscriptions or recurring list. Settings hides behind a **person glyph**, which reads as "profile". Each detail screen returns to Overview, so the hierarchy isn't real.
**Fix:**
- Tabs (iOS 26 TabView): Home · Activity · Budget · Calendar · People.
- Keep "+" as the separate trailing glass button, in the way iOS 26 sets apart a search-role tab.
- Reach Reports from a Home "Insights" row and from Budget.
- Reach Bills & subscriptions (AUD-20) from Home Upcoming "See all" and from Calendar.
- Use a gear for Settings, or put Settings in the Home toolbar menu.
- Each tab owns a NavigationStack so Back always works.

### AUD-15 · Overdue items and overspending aren't surfaced on Home
**Screens:** Home, Voice · **Effort:** S
**Problem:** Calendar has an overdue bill (electricity, 5 Oct) and Budget shows Dining out over by Rs 1,450, yet Home shows neither (DSH-07). Asked "what's my next payment?", Voice also skips the overdue bill.
**Fix:** Add an alert strip at the top of Home, shown only when needed and dismissable per item: "1 overdue · Office electricity Rs 12,800 · Pay". Over-budget appears as a line under Budget left. Voice answers should mention overdue items first.

### AUD-16 · Category tree and colours differ on every screen
**Screens:** Add transaction, Budget, Home, Reports, Calendar · **Effort:** S
**Problem:**
- Add offers Food, **Fuel**, Bills, **Office**, Other, which mixes a top-level category with a subcategory.
- Budget splits "Food & groceries" from "Dining out", while Home and Reports merge them into "Food & dining".
- Appendix A has Food › Dining out.
- Colours change from screen to screen. Subscriptions is purple in Budget but pink in Home and Reports. Shopping is cyan in Budget but purple elsewhere. Food is orange in Add but blue elsewhere. Kameti is green on Home (the income colour) and orange on Calendar.
- Picking the "Office" category and the "Office" group for one expense is ambiguous.

**Fix:** One two-level tree (Appendix A) with one fixed colour and SF Symbol per top-level category, used everywhere. The Add chips show the most frequent *subcategories* with the parent as a caption, plus "All categories…". Picking a group should not require an Office category.

### AUD-17 · Accessibility: colour-only signals, small targets, Dynamic Type
**Screens:** All · **Effort:** M
**Problem:**
- Calendar dots are colour-only and capped at 3 (A11Y-03).
- The Home donut legend lists only 3 of 5 slices.
- Owed and owe amounts depend on green and red.
- Tap targets are under 44 pt: Calendar chevrons 36, Budget chevrons about 28, Voice close 32, Shared + 36.
- All type is fixed px, and the two-column card grids with 22–24 px figures will truncate at accessibility sizes (A11Y-01).
- No VoiceOver summaries are specified for charts (A11Y-02).

**Fix:**
- Use shaped or symbol markers on the calendar, or a count badge, with VoiceOver labels like "8 October, 2 items, 1 bill due".
- The donut legend lists every slice.
- Owed and owe labels always include the words "owes you" and "you owe", which most rows already do; make it universal.
- Minimum 44 pt targets.
- Specify AX layouts where two-column cards stack and amounts wrap, never truncate.
- Write chart summaries.

### AUD-18 · Dark mode isn't designed
**Screens:** All · **Effort:** M
**Problem:** Every colour is hard-coded for light mode (#F2F2F7, #FFFFFF, black text, white glass), though NFR-04 requires dark mode. The Voice screen's black frame and rainbow halo, and the black mic button, will behave unpredictably in dark mode.
**Fix:** Define semantic colour tokens (systemGroupedBackground, secondarySystemGroupedBackground, label, secondaryLabel, plus status green, red and orange in tuned dark variants). Mock dark versions of Home, Add, Activity, Calendar and Voice.

---

## Should add

### AUD-19 · Accounts list and account detail
**Screens:** new; entry from the Home balance card and Settings · **Effort:** M
**Problem:** The PRD treats accounts as the foundation (ACC-01…05), and the owner uses 9 of them, but there is no accounts screen.
**Fix:**
- Accounts list grouped by type (Bank, Wallet, USD), each with its native balance and a PKR equivalent, plus an include-in-totals indicator.
- Account detail with a balance trend and its transactions.
- Actions: "Adjust balance" (reconcile, shown as a visible Adjustment), Transfer, Import statement, Archive.

### AUD-20 · Bills & subscriptions hub
**Screens:** new; back target for Subscription · **Effort:** M
**Problem:** No list of recurring items exists, although the owner has many subscriptions plus office payroll and rent (REC-01…04). Reports quotes "Rs 21,900 a month · 9 active", which can't be checked anywhere.
**Fix:**
- One list with sections Due now, Upcoming, Income (salary $1,875, reimbursement) and Paused/Cancelled.
- A header showing monthly and yearly totals in PKR.
- An "Add recurring" form covering REC-01 fields, including split with a group (office rent and salaries).
- Make the Pause and Cancel buttons on Subscription work.

### AUD-21 · Kameti and car installment detail
**Screens:** new; from Home, Calendar, Bills hub · **Effort:** M
**Problem:** The kameti (KAM-01…04) and the car installment (LOAN-06) are the owner's biggest fixed outflows but have no screens. Calendar shows "5 of 12" and "14 of 36" with no way to see more.
**Fix:**
- **Kameti:** a progress strip of 12 months with paid ticks, contributed Rs 100,000 of 240,000, payouts (Dec Rs 150,000 expected, Jun Rs 150,000), and a net line. The net line also exposes the open 240k-versus-300k question from Discovery.
- **Installment:** paid 14 of 36, remaining amount, next due date, and a schedule list.
- Both use the shared Mark-paid sheet (AUD-10).

### AUD-22 · Person detail that combines loans and shared expenses
**Screens:** Loan → Person · **Effort:** M
**Problem:** The Loan screen covers loans only. SPL-01 asks for one balance per person combining loans and splits, and Add already lets you split with Usama. The screen also lacks lend more, borrow, due date, interest, write off and editing the follow-up reminder. The "Owes you" label stays even when the balance shows "Settled".
**Fix:** Rename the screen to the person's name. The header shows the net balance with a breakdown (loans Rs 25,000 · shared Rs 0). Actions: Record repayment, Lend or borrow, Settle up, Remind. One combined history. The label switches to "All settled".

### AUD-23 · Group detail and settle-up sheet
**Screens:** Shared → Group · **Effort:** M
**Problem:** The Office group expands inline as an accordion with no dates or month filter. SPL-12 (activity feed by month) and RPT-06 (monthly Office settlement) aren't met, and the other groups don't open.
**Fix:** Push a Group page showing the balance per member, a month picker in the title menu, the activity list with dates and "who paid", month totals, and a "Settle up" sheet (amount editable, account, date, partial allowed). Simplify debts (SPL-09) applies only to groups with 3 or more people. Add a "New group" flow behind the + button.

### AUD-24 · Budget setup and limit editing
**Screens:** Budget · **Effort:** M
**Problem:** There is no setup flow (BUD-01…05). The category limits add up to Rs 157,000, but the total is Rs 180,000, and the **Rs 23,000 unassigned** isn't shown. The subscriptions limit (Rs 15,000) is below the known subscription cost (Rs 21,900 a month in Reports). The 80% warning threshold can't be set.
**Fix:**
- Edit Limits screen: total, then per-category limits with a running "unassigned" line.
- Suggest limits from the last 3 months and from recurring commitments, with a warning when a limit is below committed bills.
- Threshold setting.
- Group budgets section.
- "Copy to next month" happens automatically, with a note saying so.

### AUD-25 · Budget category drill-down and history
**Screens:** Budget · **Effort:** S
**Problem:** Category rows aren't tappable, the month arrows don't work, and BUD-06 (history per month and category) has no screen.
**Fix:** Tapping a category opens its transactions for the month (shares included, see AUD-02) and a 6-month bar chart of spend against limit. Make the month controls work, or replace them with a title menu listing months.

### AUD-26 · Transaction detail and edit, with receipts, tags and Recently Deleted
**Screens:** new; from Activity, Calendar, search · **Effort:** M
**Problem:** There's no screen to view, edit, duplicate or delete a transaction (TXN-04, TXN-07, ATT-01), and no Recently Deleted list (DATA-01), though Settings says "3 items".
**Fix:**
- Detail screen with amount, type, account, category, payee, tags, split breakdown, attachments (on-device receipt reading, AI-02) and a linked loan or recurring item.
- Toolbar actions: Edit, Repeat, Delete.
- A Recently Deleted list with Restore and days left.

### AUD-27 · Onboarding and first run
**Screens:** new · **Effort:** M
**Problem:** There is no first-run design, though the PRD needs presets (ACC-06), opening balances, salary day, rate, fast loan entry (LOAN-08), the statement-import recommendation (IMP-05) and sample-data mode (DATA-04). An empty Home has never been designed.
**Fix:** A 5-step flow:
1. Welcome and privacy ("everything stays on this iPhone").
2. Currency: PKR base and the USD rate.
3. Accounts: preset toggles plus opening balances.
4. Income: salary $1,875 on the 21st.
5. Optional: people balances, statement import, or "Explore with sample data".

Permission requests come later, in context.

### AUD-28 · Statement PDF import and review
**Screens:** new; from Settings and account detail · **Effort:** L
**Problem:** IMP-01…06 are M priority but have no screens, and import is how the owner loads his history.
**Fix:** Flow: choose account, pick the PDF, then a parsing state. A review list shows rows with suggested categories, "Possible duplicate" flags with the matched row, and exclude toggles, plus a summary ("124 new, 6 duplicates, 3 excluded"). Then Import. Add an "Unsupported format" state with the steps to send a sample.

### AUD-29 · Reminders: create events, set lead times, design notifications
**Screens:** Calendar, Subscription, Settings, Lock Screen · **Effort:** M
**Problem:** Calendar has no "+" for custom events or reminders (CAL-03). Subscription hard-codes "Remind me 1 day before", so the per-item lead time and time (CAL-04) can't be set. The notifications themselves, with Mark paid, Snooze 1 day and Open (§15), and the hidden-amount variant (SEC-04), aren't designed. Calendar opens on the 8th, not today.
**Fix:**
- Calendar toolbar "+" opens a New reminder sheet: title, optional amount, date, repeat, lead time.
- Each item's reminder row reads "1 day before at 10:00 ▾".
- Mock a Lock Screen notification and its expanded actions.
- Add a "Today" button, and open on today.
- Consider a list (agenda) view inside the same screen, chosen from the toolbar menu rather than a segmented control.

### AUD-30 · Complete the Reports screen
**Screens:** Reports · **Effort:** M
**Problem:**
- There's no period picker (RPT-01 says "any month or range").
- Budget performance (RPT-03), owed/owing per person (RPT-05), account balances over time (RPT-07) and cash-flow trend are missing.
- The tiles and the PDF button do nothing.
- "Income vs spending" doesn't say whether it's in PKR or at which rate.

**Fix:** Add a period menu in the toolbar and sections for budget against actual by month, people balances and net position. Tiles drill into the Bills hub (AUD-20) and Group (AUD-23). PDF export opens a preview and the share sheet. Add a footnote: "Shares only · transfers excluded · USD at 280".

### AUD-31 · Data, security and preference screens behind Settings
**Screens:** Settings · **Effort:** M
**Problem:**
- Backup has only a "Never backed up" label. There's no password step, no Restore with summary (DATA-02, §13), and no export options screen.
- These settings are missing: Currency & rate editor (CUR-03), salary day and budget threshold (SET-03), lock timeout, "hide amounts in app switcher" (SET-02), and sample data (DATA-04).
- Face ID is on by default in the mockup, but the PRD says off.

**Fix:**
- Design the Backup sheet (set password, save to Files, last-backup date and size) and Restore (pick file, enter password, summary, "replace data" confirmation).
- Add the missing settings rows and a Sample data section with "Remove sample data".
- Default Face ID to off.
- Show a backup nudge on Home after 30 days without one.

### AUD-32 · Empty, loading and error states
**Screens:** Home, Activity, Budget, People, Reports, Voice, Import · **Effort:** S
**Problem:** Only Calendar has an empty state ("Nothing due. Enjoy the day."). There's no design for: a new user with no data, no budget set, search with no results, Voice unavailable or permission denied (VOX-08), calendar permission denied, or a failed import.
**Fix:** One illustration-free pattern in the style of ContentUnavailableView, each with a single clear action. Examples: "Set a budget", "Add an account", "Use the keyboard instead" for Voice, "Open Settings" for permissions.

### AUD-33 · Voice: typing, editable card, smarter follow-ups, unavailable state
**Screens:** Voice · **Effort:** M
**Problem:**
- No text input, which matters in quiet places, for accessibility, and for public users.
- The confirmation card's From and Date fields aren't editable inline.
- "Listening" shows constantly, even while the answer is displayed.
- After "they'll return it later" the assistant doesn't ask *when*, though LOAN-07 needs a follow-up date.
- The rainbow edge glow imitates Apple Intelligence's Siri, which may confuse users about which assistant they're using.
- The mic is reachable only from a black floating button on Home that sits above the tab bar, overlapping content and crowding the + button.

**Fix:**
- Add a "Type" field next to the mic.
- Card rows become tappable pickers.
- Show explicit states: idle, listening, thinking, answered.
- Ask a follow-up: "When should I remind you? (e.g. end of month)".
- Use UZee's own subtle accent glow.
- Move "Ask UZee" into the + button long-press menu and a Home toolbar button, or the iOS 26 tab bar accessory, so it's reachable from every tab without a second floating button.

### AUD-34 · iPad layout
**Screens:** all · **Effort:** M
**Problem:** NFR-02 requires iPad in portrait, landscape and split view. No iPad layout exists.
**Fix:** NavigationSplitView with a sidebar (Home, Activity, Budget, Calendar, People, Reports, Bills, Accounts, Settings), list and detail columns for Activity and People, a larger Calendar with day detail on the side, and Add as a form sheet. Mock one landscape and one split-view frame.

### AUD-35 · System entry points: Action Button, Control Center, Lock Screen, Shortcuts
**Screens:** system surfaces · **Effort:** S
**Problem:** VOX-01 is M priority and names Action Button, Lock Screen and Control Center invocation plus "Hey Siri, ask UZee". The only design is a Settings row.
**Fix:** Design the Control Center and Lock Screen controls (Ask UZee, Quick add), the Siri snippet view for an answer and for a confirmation, and an App Shortcuts list in Settings › Siri & voice.

---

## Nice to have

### AUD-36 · Clearer Home card meanings
**Screens:** Home, Budget · **Effort:** S
**Problem:**
- The "Budget left" ring fills to 64%, which is the *used* share, beside the word "left".
- The "Spent" card's five grey bars have no labels.
- "8% less than September" compares 6 days with a full month.
- "Upcoming" includes 15 Oct, 9 days out, though DSH-02 says 7 days.
- "Safe to spend … for 25 days" should be 26 days counting today.

**Fix:** Make the ring show what's left, or label it "64% used". Replace the bars with "Rs X less than this time in September". Fix the upcoming window or retitle it "Before salary". Get the day count right.

### AUD-37 · Native iOS 26 components and motion
**Screens:** all · **Effort:** S
**Problem:** Several parts are hand-built where iOS 26 has native equivalents: headers, back links, switches, the bottom sheet and the tab bar. The entrance animations are long: 0.75 s rise, 1.4 s ring, and a 1.1 s balance count-up on every open. That works against "see balance within 1 s" (OBJ-1) for an app opened several times a day.
**Fix:**
- Specify NavigationStack large titles with glass toolbar buttons, and Form or List for Settings and details.
- Add uses sheet detents, medium with the keypad and large for split.
- Use system menus and context menus, and haptics on save and settle.
- Run the count-up only on the first launch of the day, or when the value changes.
- Keep springs to 0.35–0.5 s.
- Honour Reduce Motion, which the mockup already does.

### AUD-38 · Swipe actions, context menus and "Repeat"
**Screens:** Activity, Calendar, People · **Effort:** S
**Problem:** Common actions need several taps. TXN-07 (repeat) has no affordance.
**Fix:** Activity rows: swipe for Repeat and Delete, and a long-press menu with Edit, Split, Change category and Repeat. Calendar rows: Paid and Skip. People rows: Settle and Remind.

### AUD-39 · Salary-day conversion assistant and FX gain/loss
**Screens:** Home, Transfer · **Effort:** M
**Problem:** Every month, about the 21st, the owner converts USD from Wise to PKR. The app records it but doesn't help.
**Fix:** When the salary is marked received, suggest "Move to HBL?" with the last used rate pre-filled. Track the difference between the actual rate and the 280 table rate, e.g. "Received Rs 1,350 less than at 280". This is useful to any remittance earner and isn't niche.

### AUD-40 · Optional pay-cycle budget period (21st to 20th)
**Screens:** Budget, Settings · **Effort:** M
**Problem:** The owner is paid on the 21st, but budgets run by calendar month (BUD-01). "Until next salary" already hints that the salary cycle is how he thinks.
**Fix:** Offer a setting: budget period = calendar month or salary cycle. Keep the calendar month as the default to stay within the PRD. Flag it as a PRD change if adopted.

### AUD-41 · Send a polite reminder to a person
**Screens:** Person detail, Group · **Effort:** S
**Problem:** Follow-up reminders only notify the owner. The real action is messaging Usama or the partner.
**Fix:** A "Remind" button opens the share sheet with editable text, e.g. "Hi Usama, just a reminder about Rs 25,000 from 2 Sep and today." No network or accounts are needed, so it suits v1's offline design.

### AUD-42 · Generic service icons instead of brand logos
**Screens:** Subscription, Bills hub · **Effort:** S
**Problem:** The Netflix screen uses a Netflix-red tile and glyph. That's fine for personal use, but it's a trademark problem for a public release, and it doesn't scale to "many more" services.
**Fix:** The user picks an SF Symbol and colour, or the icon defaults to a monogram tile. Keep any brand assets out of the app bundle.

---

## Future

### AUD-43 · Home Screen and Lock Screen widgets
**Screens:** widgets · **Effort:** M
**Problem:** Already a PRD future candidate. Budget left and next due are the most-checked numbers.
**Fix:** Small widget: budget left with a ring. Medium: available balance plus the next 3 dues, with an interactive "Paid" button. Lock Screen: inline budget-left text. Hide amounts when the app lock is on.

### AUD-44 · Capture bank SMS and wallet alerts through Shortcuts
**Screens:** Settings › Automations · **Effort:** L
**Problem:** Pakistani banks and wallets send SMS or app alerts for every transaction. Typing each one is the main source of missed entries.
**Fix:** A documented Shortcuts automation passes the message text to a "Log from text" App Intent. The on-device parser proposes a transaction, which appears as a "To review" item. Never auto-post.

### AUD-45 · Regional extras (niche, keep optional)
**Screens:** Settings, Reports · **Effort:** L
**Problem:** Some features would help Pakistani users a lot but are niche for a general public release.
**Fix:** Keep them as optional modules, off by default: a Zakat estimate from account balances (Charity › Zakat already exists) and Urdu or Roman Urdu voice once the on-device model supports it. Don't let either shape the core navigation.
