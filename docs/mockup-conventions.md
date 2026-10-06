# Mockup conventions for the audit rework (read with mockup-dataset.md and design-audit.md)

Folder: /tmp/claude-0/-home-claude-Uzee/5d5d879d-2b01-59dd-9c35-44cee6d669ea/scratchpad/uzee-design/project/
Each screen is one `Name.dc.html` file in that folder. Read 2 existing files (e.g. Activity.dc.html, AddTransaction.dc.html) first and copy their exact structure:
- `<script src="./support.js"></script>` in head; all markup inside `<x-dc>`; CSS inside `<helmet><style>…</style></helmet>`.
- Logic in `<script type="text/x-dc" data-dc-script data-props='{"$preview":{"width":390,"height":844}}'>` with `class Component extends DCLogic { renderVals() { … return {…}; } }`. State via `this.state` (may be undefined at first) and `this.setState({...})`.
- Template holes `{{name}}` / `{{item.field}}` only reference values returned by renderVals. Loops: `<sc-for list="{{xs}}" as="x" hint-placeholder-count="3">`. Conditionals: `<sc-if value="{{flag}}" hint-placeholder-val="{{ false }}">`. Events: `onClick="{{fn}}"`, `onInput="{{fn}}"` (handler receives the event). Holes may sit inside style values as the existing files do.
- Navigation is plain `<a href="Other.dc.html">`. Every chevron, tinted text or button must either do something (state change, toast, sheet) or link to a real file from the file map below. No dead controls (AUD-11).
- Phone frame: root div 390×844, `position:relative; overflow:hidden`. iPad file: 1180×820.

Visual language (keep it premium, Apple iOS 26):
- SF system font stack, large 34px bold titles, grouped cards radius 20, tabular numbers (`.num`), glass tab bar, springs `cubic-bezier(.2,.9,.25,1.08)` 0.35–0.5 s, `.press` scale on tap, honour prefers-reduced-motion.
- Use CSS variables declared on the root div's class, so a dark variant is the same file with another class: `--bg #F2F2F7 / #000000`, `--card #FFFFFF / #1C1C1E`, `--card2 #F2F2F7 / #2C2C2E`, `--label #000 / #FFF`, `--label2 #6C6C70 / #98989F`, `--sep #E5E5EA / #38383A`, `--fill rgba(118,118,128,.12) / rgba(118,118,128,.24)`, `--tint #007AFF / #0A84FF`, `--green #248A3D / #30D158`, `--red #D70015 / #FF453A`, `--orange #C93400 / #FF9F0A`, glass `rgba(255,255,255,.72) / rgba(30,30,30,.72)`.
- No segmented controls or chip-row tabs at the top of screens (owner rule, AUD-07). Use pull-down menus (a token like "Expense ▾" opening a small glass menu), toolbar buttons, and title menus instead.
- Min 44px tap targets. Status never by colour alone (use words or a symbol: ✓ paid, ! overdue).
- Category colours are fixed (see dataset). Use simple stroked SVG icons like the existing files.
- Brand logos are not used: subscriptions get a monogram tile or generic symbol in a user colour (AUD-42).

Tab bar on every tab-level screen (AUD-14): glass pill with Home (Main.dc.html) · Activity · Budget · Calendar · People (People.dc.html), plus a separate trailing round glass "+" button linking to AddTransaction.dc.html. Detail screens have a back link naming the screen they came from, and no tab bar if they are pushed sheets.
Home toolbar (top right): mic button → Voice.dc.html and gear → Settings.dc.html. There is no floating black mic button any more (AUD-33).

File map (final names; link only to these):
Main (Home), HomeDark, AddTransaction, AddTransfer, Split, MarkPaid, Activity, ActivityDark, TxnDetail, Budget, BudgetLimits, Calendar, Bills (Bills & subscriptions hub incl. kameti and car installment), Subscription (Netflix detail), Notifications (lock screen, Control Center, widgets, Siri), People (tab; replaces Shared), Group (Office group), Person (Usama; replaces Loan), Voice, Reports, Settings, Accounts, Onboarding, Import, Backup (backup, restore, Recently Deleted), EmptyStates, iPad.

Money actions never save in one tap: they open a confirm sheet (amount, account, date editable) and then show a toast "Saved · Undo" (AUD-13).

Verify before finishing: extract each file's x-dc script and run `node --check` on it (wrap as needed), check every `{{hole}}` you used is returned by renderVals, every href points to a file in the map, and every number matches mockup-dataset.md exactly.
