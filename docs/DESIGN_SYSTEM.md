# UZee — Design System

| | |
|---|---|
| Version | 0.1 · 2026-10-06 |
| Platform | Native SwiftUI, iPhone + iPad, iOS/iPadOS 26 (Liquid Glass), no third-party UI libraries |
| Sources | Approved mockups (`uzee-design/project/*.dc.html`), PRD v0.3 (NFR-02/04, A11Y-01…04, SET-02, Appendix A), `mockup-conventions.md`, `mockup-dataset.md`, `design-audit.md` (AUD-xx), tech-decisions brief |
| Code home | `UZeeUI` package → `DesignSystem/` (tokens, components). Feature screens consume only these; no raw hex or font sizes in feature code. |

**Principles, in priority order:** 1) numbers are correct and readable (tabular, currency always shown); 2) fast entry (one sheet, keypad first, smart defaults); 3) Apple-native (system components, materials and motion before custom ones); 4) minimal clutter (one primary action per screen, no decorative chrome); 5) accessible by default (Dynamic Type to AX5, VoiceOver, never colour alone); 6) consistent (same token, same component, same words everywhere).

---

## 1. Colour tokens

Defined once in `UZColor` (Asset Catalog colour sets with Any/Dark + High Contrast variants where noted). Prefer the system semantic colour; a custom asset exists only where the system value fails WCAG AA for small text.

| Token | Light | Dark | SwiftUI | Use |
|---|---|---|---|---|
| `bg` | #F2F2F7 | #000000 | `Color(.systemGroupedBackground)` | Screen background |
| `card` | #FFFFFF | #1C1C1E | `Color(.secondarySystemGroupedBackground)` | Cards, grouped rows |
| `card2` | #F2F2F7 | #2C2C2E | `Color(.tertiarySystemGroupedBackground)` | Nested surfaces inside a card |
| `label` | #000000 | #FFFFFF | `Color(.label)` / `.primary` | Titles, amounts |
| `label2` | #6C6C70 | #98989F | Asset `uzSecondaryText` (≈ system “accessible” secondary) | Captions, meta lines. System `.secondaryLabel` (60 % alpha) is ~3.4:1 on white; the asset keeps ≥ 4.5:1 |
| `label3` | #C7C7CC | #48484A | `Color(.tertiaryLabel)` | Chevrons, placeholder only (never information) |
| `sep` | #E5E5EA | #38383A | `Color(.separator)` (0.5 pt hairline) | Row dividers |
| `fill` | rgba(118,118,128,.12) | rgba(118,118,128,.24) | `Color(.tertiarySystemFill)` | Tokens, fields, steppers, pressed rows, inactive tab pill |
| `tint` | #007AFF | #0A84FF | `.accentColor` / `.tint(.blue)` (Color(.systemBlue)) | Links, toolbar actions, selection |
| `positive` | #248A3D | #30D158 | Asset `uzPositive` | Income, “owes you”, paid ✓, under budget |
| `negative` | #D70015 | #FF453A | Asset `uzNegative` | “You owe”, overdue !, over budget, destructive |
| `warning` | #C93400 | #FF9F0A | Asset `uzWarning` | Due soon, estimated, near limit |
| `scrim` | rgba(0,0,0,.32) | rgba(0,0,0,.55) | System sheet/alert dimming (custom overlays only) | Behind custom popovers |
| `skeleton` / `skeleton2` | rgba(118,118,128,.14 / .26) | rgba(118,118,128,.22 / .36) | `.redacted(reason: .placeholder)` default fill | Loading placeholders |
| `toastBg` | rgba(28,28,30,.92) | same | `.glassEffect(.regular.tint(.black.opacity(0.6)), in: .capsule)` | UndoToast |

Rules
- Expense amounts are `label`, not red. Only income (+, `positive`) and debt direction use colour. Transfers use `label2`.
- Status colours always come with a word or a symbol (✓ / ! / clock) — A11Y-03.
- Status-tinted backgrounds use the status colour at 14–16 % opacity (`color.opacity(0.15)`).
- Increase Contrast (`@Environment(\.colorSchemeContrast) == .increased`): assets provide High Contrast variants; hairlines become 1 pt; glass falls back per §7.

## 2. Category colours and symbols (fixed everywhere — AUD-16, PRD Appendix A)

Colour and symbol belong to the **top-level** category; subcategories inherit them. Map via `CategoryStyle(for: Category.Kind)` in `UZeeUI`; never pick colours per screen. All are system colours, so dark variants are automatic.

| Category | SwiftUI colour | Light | Dark | Glyph on 15 % tile (light, for contrast) | SF Symbol |
|---|---|---|---|---|---|
| Office | `Color(.systemIndigo)` | #5856D6 | #5E5CE6 | #5856D6 | `building.2.fill` |
| Transport | `Color(.systemBlue)` | #007AFF | #0A84FF | #007AFF | `car.fill` |
| Food | `Color(.systemOrange)` | #FF9500 | #FF9F0A | #C93400 | `fork.knife` |
| Personal | `Color(.systemTeal)` | #30B0C7 | #40C8E0 | #1E7F91 | `bag.fill` |
| Utilities | `Color(.systemYellow)` | #FFCC00 | #FFD60A | #A07800 | `bolt.fill` |
| Subscriptions | `Color(.systemPink)` | #FF2D55 | #FF375F | #D70045 | `arrow.triangle.2.circlepath` |
| Financial | `Color(.systemMint)` | #00C7BE | #63E6E2 | #00A39B | `banknote.fill` |
| Health | `Color(.systemRed)` | #FF3B30 | #FF453A | #D70015 | `cross.case.fill` |
| Income | `Color(.systemGreen)` | #34C759 | #30D158 | #248A3D | `arrow.down.circle.fill` |
| Transfer | `Color(.systemGray)` | #8E8E93 | #98989D | #6C6C70 | `arrow.left.arrow.right` |
| People / loans | `Color(.systemPurple)` | #AF52DE | #BF5AF2 | #8E3CB8 | `person.2.fill` |

Other Appendix A categories (proposed, not in the sample data; owner may change): Housing `Color(.systemBrown)` `house.fill`; Family `Color(.systemPurple)` `figure.2.and.child.holdinghands`; Education `Color(.systemCyan)` `book.fill`; Entertainment `Color(.systemIndigo)` `ticket.fill`; Charity `Color(.systemGreen)` `hand.raised.fill`; Other `Color(.systemGray)` `ellipsis.circle.fill`. Where a colour repeats, the symbol and name disambiguate.

Tile rendering
- Default tile: `RoundedRectangle(cornerRadius: 10, style: .continuous)` 36 pt (rows) or radius 15 / 48 pt (Add sheet chips), fill = colour at 15 %, glyph in the “glyph on tile” value (light) or the dark system colour (dark).
- Selected chip: solid category colour, white glyph (Utilities: black glyph), soft shadow `color.opacity(0.33)` radius 8 y 6.
- Tiles are decorative (`.accessibilityHidden(true)`): the category **name** is always visible next to them.

## 3. Typography

SF Pro via `Font.TextStyle`, so everything scales with Dynamic Type. No fixed sizes in feature code. Sizes below are at the default (Large) setting and match the mockups.

| Token | Mockup | SwiftUI | Use |
|---|---|---|---|
| `heroAmount` | 44 / Bold, tracking −0.04 em | `.system(size: s, weight: .bold)` with `@ScaledMetric(relativeTo: .largeTitle) var s = 44` + `.monospacedDigit()` | Available balance, amount being entered |
| `largeTitle` | 34 / Bold, −0.03 em | `.largeTitle.bold()` (system nav large title) | Screen titles |
| `entryAmount` | 30 / Bold | `.system(size: s, weight: .bold)`, `@ScaledMetric(relativeTo: .title) var s = 30` | Confirm/Split amount |
| `keypad` | 28 / Regular | `.title` | Keypad digits |
| `cardValue` | 22 / Bold | `.title2.bold()` + `.monospacedDigit()` | Card headline numbers |
| `section` | 20 / Bold, −0.02 em | `.title3.bold()` + `.accessibilityAddTraits(.isHeader)` | Section headers (“Upcoming”, “Groups”) |
| `headline` | 17 / Semibold | `.headline` | Card titles, sheet titles, primary button labels |
| `body` | 17 / Regular | `.body` | Form rows, list text |
| `rowTitle` | 16 / Medium–Semibold | `.callout.weight(.medium)`; amounts `.callout.weight(.semibold)` | List row title and row amount |
| `subhead` | 15 / Semibold | `.subheadline.weight(.semibold)` | Tokens, links, small buttons, toast |
| `footnote` | 13 / Regular–Semibold | `.footnote` | Meta lines, captions, grouped-list headers (uppercase via `.textCase(.uppercase)` only in List headers) |
| `caption` | 12 / Regular–Semibold | `.caption` | Card sub-lines, “≈ Rs” lines, badges |
| `caption2` | 11 / Bold | `.caption2.bold()` | StatusBadge, footnotes like “USD at $1 = Rs 280” |
| `tabLabel` | 10 / Semibold | system tab bar | Not set manually |

Rules
- Every number: `.monospacedDigit()` (tabular digits) — the mockups’ `.num` class. Hero and card amounts also `.contentTransition(.numericText(value:))`.
- Weights: Bold for titles and hero/card amounts; Semibold for headings, row amounts, buttons; Regular/Medium for everything else. No Light/Thin.
- Line limits: titles and payees `lineLimit(1…2)` with `.truncationMode(.tail)`; amounts never truncate — they move to their own line (see §18).
- Text style `.system(.body, design: .default)` only; no rounded or serif designs.

## 4. Money display rules

All formatting goes through one formatter, `MoneyFormatter` (UZeeCore `Money` → `String`), and one view, `AmountText`. Never format money inline.

| Rule | Detail | Example |
|---|---|---|
| Symbol always | `Rs` for PKR (with a space), `$` for USD; other ISO codes use `Locale` symbol. Never a bare number. | `Rs 182,400` · `$520.00` |
| Minor units | PKR always displays whole rupees (rounded half-up for display only; storage keeps paisa), so $2.99 × 280 shows as Rs 837; USD always 2 decimals. Input: PKR keypad has “000”, USD keypad has “.” (AUD-05). | `Rs 3,250` · `$2.99` |
| Signs | True minus “−” (U+2212) for outflow in lists, “+” for inflow (income green). Hero balance and cards have no sign. | `−Rs 1,600` · `+$1,875.00` |
| Native first | A USD amount shows native on line 1, `≈ Rs 5,600` on line 2 (`caption`, `label2`). | `$20.00` / `≈ Rs 5,600` |
| Mixed totals | Any PKR total that includes USD carries the footnote `USD at $1 = Rs 280` (tappable → rate editor). Balance card adds the breakdown line. | `Rs 300,000 + $660 · USD at 280` |
| Transfers | Both legs + actual rate. | `−$500.00` / `+Rs 139,350 · 278.70` |
| Splits | Main number = account movement; second line = `your share Rs 1,600`. A bill paid by someone else shows `No account movement`. | |
| Debt direction | Always words + colour: `owes you` (`positive`) / `you owe` (`negative`) / `settled` (`label2`, ✓). Colour alone is never used. | `Usama owes you Rs 25,000` |
| Over/under | Always words + symbol: `! Personal over by Rs 1,200`, `Rs 9,800 less than this time in September`. | |
| Hide amounts | Setting “Hide amounts” (and app-switcher snapshot when lock is on, SET-02): `AmountText` renders `Rs •••••` keeping the currency symbol; VoiceOver reads “amount hidden”. Implement with `.privacySensitive()` + `.redacted(reason: .privacy)` environment; the app-switcher overlay is a full-screen blur on `scenePhase != .active`. Notifications use `Rs •••••` when the notifications option is on. | `Rs •••••` |
| Large values | Group with locale separators (en_PK: 1,000,000 not 10,00,000 unless owner opts in). Compact `Rs 2.7M` only in chart axes. | |

## 5. Spacing and layout

Base unit 2 pt; use the scale only. Constants in `UZSpacing`.

| Token | pt | Use |
|---|---|---|
| `xxs` | 2 | Title ↔ sub-line inside a row |
| `xs` | 4 | Icon ↔ label in tokens; card internal stack (tight) |
| `s` | 6 | Section header ↔ card; legend rows |
| `m` | 8 | Toolbar button gap; chip gap |
| `ml` | 10 | Row element gap; status bar gap |
| `l` | 12 | Row icon ↔ text; sheet section gap |
| `xl` | 14 | Gap between Home cards (iPhone) |
| `xxl` | 16 | Screen gutter (iPhone); card padding; iPad card gap |
| `xxxl` | 20 | Hero card horizontal padding; iPad card padding |

| Layout rule | Value |
|---|---|
| Screen side gutter | 16 pt iPhone (`.contentMargins(.horizontal, 16)` / List default), 20 pt iPad regular width |
| Card padding | 16 pt; hero balance card 18 top / 20 sides; list cards 0 vertical / 16 horizontal |
| Row min height | 44 pt hit target; standard rows 48 pt; two-line rows 56–60 pt |
| Bottom clearance | Content insets clear the glass tab bar automatically (`safeAreaInset`); never hard-code 124 pt |
| Two-up cards | `Grid` / `LazyVGrid(columns: 2 flexible, spacing: 14)`; collapse to one column at AX sizes |

## 6. Corner radius and elevation

Always `RoundedRectangle(cornerRadius:, style: .continuous)`. Where a shape sits inside a glass container on iOS 26, prefer `ConcentricRectangle()` / `.containerShape(...)` so corners stay concentric.

| Token | pt | Use |
|---|---|---|
| `r.badge` | 8 | Inline text fields, badges, small icon tiles (30 pt Settings icons) |
| `r.tile` | 10 | 36–38 pt category/date tiles, tokens in forms |
| `r.field` | 12 | Search field, text fields |
| `r.control` | 14 | Keypad key press shape, calendar day cell, rectangular buttons in sheets |
| `r.chip` | 15 | 48 pt category tile in Add |
| `r.menu` | 16 | Custom menus/popovers (system menus use their own) |
| `r.card` | 20 | Cards, grouped sections, alerts |
| capsule | h/2 | Primary/secondary buttons (50 pt → 25), toolbar circles (44 → 22), tab bar (62 → 31), toast, StatusBadge |
| sheet | system (28 in mockups) | Never override sheet corners |

Elevation: cards are flat (no shadow) on `bg`. Shadows only on floating glass (tab bar, “+”, toolbar buttons, toast, custom menus) — the system glass provides them. Selected category chip gets a coloured soft shadow (§2).

## 7. Materials — Liquid Glass

| Element | iOS 26 implementation | Mockup reference |
|---|---|---|
| Tab bar | System `TabView` (glass automatic) | `.glass` 62 pt capsule |
| “+” add button | Separate 62 pt circle, `.glassEffect(.regular.interactive(), in: .circle)`, `tint` glyph `plus` 22 pt semibold | trailing round glass button |
| Toolbar buttons | `ToolbarItem` with `Button` + SF Symbol; system renders glass. Custom: `.buttonStyle(.glass)` 44 pt circle | `.tbtn.glass` |
| Primary floating action | `.buttonStyle(.glassProminent)` | |
| Menus, context menus | System `Menu` / `.contextMenu` (glass automatic) | `.menu` glass |
| Toast | Capsule `.glassEffect` (dark tinted), see UndoToast | `.toast` |
| Grouping | Wrap adjacent glass elements in `GlassEffectContainer(spacing: 10)` so they blend/morph | tab bar + “+” |

Rules: glass is for the **navigation/control layer only**; content (cards, lists) stays opaque `card`. Never stack glass on glass. Reduce Transparency: system glass adapts; any custom `Material` must switch to `card` when `accessibilityReduceTransparency` is true.

## 8. Icons

- SF Symbols only (no custom glyphs, no brand logos). Rendering: `.symbolRenderingMode(.hierarchical)` in tiles; `.monochrome` in toolbars and tab bar.
- Sizes: toolbar 17–20 pt (`.imageScale(.large)`), row icons follow text style (`.font(.body)`), tab icons system.
- Variant: `.fill` in tab bar (selected, system automatic) and category tiles; outline elsewhere.
- **No brand logos** (AUD-42): subscriptions and payees use `MonogramTile` (first letter, user-chosen colour, `r.tile`) or a user-picked generic symbol (`play.tv`, `music.note`, `cloud`, `sparkles`, `wifi`, `phone`). No brand assets in the bundle.

| Role | Symbol |
|---|---|
| Tabs | Home `house` · Activity `list.bullet.rectangle` · Budget `chart.pie` · Calendar `calendar` · People `person.2` |
| Add | `plus` |
| Ask UZee (Home toolbar) | `mic` (or `waveform`) |
| Settings (Home toolbar) | `gearshape` |
| Filter (Activity) | `line.3.horizontal.decrease` (`.circle.fill` when active) |
| Search | system `.searchable` |
| Paid / success | `checkmark.circle.fill` |
| Overdue / error | `exclamationmark.circle.fill` |
| Warning / near limit | `exclamationmark.triangle.fill` |
| Due / scheduled | `clock` |
| Repeat | `arrow.clockwise` |
| Receipt | `paperclip` / `doc.text.viewfinder` |
| Swap accounts | `arrow.up.arrow.down` |
| Settle up | `checkmark.seal` |
| Remind | `bell` |
| Undo | text “Undo” (not an icon) |
| Disclosure | system chevron (`NavigationLink`) — never hand-drawn |

## 9. Navigation

| Rule | Implementation |
|---|---|
| Tab structure | `TabView` with `Tab` Home, Activity, Budget, Calendar, People; each owns a `NavigationStack` with its own path (Back always works, AUD-14). |
| “+” button | Separate trailing glass circle next to the tab bar. Preferred: a sixth `Tab(value: .add, role: .search)` (iOS 26 renders it detached) whose selection is intercepted to present the Add sheet and restore the previous tab; fallback: overlay glass button in a `GlassEffectContainer`. Long-press `Menu`: Expense · Income · Transfer · Lend or borrow · Settle up · Ask UZee. Decide in M1 on device. |
| Tab bar behaviour | `.tabBarMinimizeBehavior(.never)` — “+” must always be reachable. |
| Titles | Large titles (`.navigationBarTitleDisplayMode(.large)`) on tab roots; inline on detail screens. Home shows the date as a small uppercase kicker above the title. |
| Back labels | System back button; label = previous screen title (no custom back text). |
| **No segmented controls or chip-row tabs at the top of screens** (owner rule, AUD-07) | Switch views and filters with: `.toolbarTitleMenu { }` (e.g. month on Budget/Calendar: “October ▾”), a toolbar `Menu` (Activity filter `line.3.horizontal.decrease`), or a pull-down token beside a value (“Expense ▾”). Active filters appear as removable tokens in the search field (`.searchable(text:tokens:)`). `Picker(.segmented)` is not used anywhere at the top of a screen; inside forms use `Picker` with `.menu` style. |
| Home toolbar | Trailing: `mic` → Ask UZee, `gearshape` → Settings. No floating mic (AUD-33). |
| Detail destinations | Every chevron / tinted text has a destination or action (AUD-11). |
| Swipe & context | Activity rows: leading Repeat, trailing Delete; `.contextMenu` Edit · Split · Change category · Repeat. Calendar/Home due rows: leading “Paid”, trailing “Skip”. People rows: Settle · Remind. |

## 10. Modal behaviour

| Surface | Use | SwiftUI |
|---|---|---|
| Add transaction sheet | Quick entry, keypad visible | `.sheet` · `.presentationDetents([.medium, .large])` starting `.large` on small phones if keypad + chips don’t fit (`ViewThatFits`); `.presentationDragIndicator(.visible)` |
| Split editor | “With”, “Paid by”, members | Pushed inside the Add sheet’s `NavigationStack`, sheet goes `.large` |
| ConfirmSheet (money actions) | Pay bill, repayment, settle up, adjust balance | `.sheet` · `.presentationDetents([.medium])` (`.large` at AX sizes); amount, account, date pre-filled and editable |
| Pickers (person, account) | Search + list | `.sheet` `.large` with `.searchable`; or inline `Menu` when ≤ 10 options |
| Menus | Type, account, date presets, method | `Menu` / `Picker(.menu)`; never a custom modal |
| Destructive confirm | Delete, discard, replace data | `.confirmationDialog` (iPhone action sheet / iPad popover), destructive role |
| Alerts | Blocking errors only (restore failed, password wrong) | `.alert` |
| Toast | Result of an action with Undo | `UndoToast` overlay, never modal |
| iPad | Add, Confirm, Split | `.presentationSizing(.form)`; pickers as `.popover` |

Rules
- **Money actions never save in one tap** (AUD-13): tap → ConfirmSheet (editable) → Save → sheet dismisses → `UndoToast` “Saved · Undo” for 5 s. Undo reverses the write in one transaction; the undone entry also lands in Recently Deleted.
- Dirty sheets: `.interactiveDismissDisabled(isDirty)`; Cancel or swipe-down on a dirty sheet shows `confirmationDialog` “Discard changes?” (Discard / Keep editing).
- Save disabled until valid (amount > 0 and category set; split “Rs 0 left to assign”). Disabled state is `.disabled(true)` (system dims), with the reason shown as a caption, not only by dimming.
- Toolbar placement inside sheets: Cancel `.cancellationAction`, Save/Done `.confirmationAction` (bold).
- One sheet at a time; never present a sheet from a sheet except pickers.

## 11. Component catalogue (`UZeeUI/DesignSystem`)

| Component | Purpose | Key states | Accessibility label rule |
|---|---|---|---|
| `AmountText` | Renders a `Money` with all §4 rules (symbol, sign, tabular, `≈ Rs` line, hide mode) | normal · positive · negative-direction · transfer · hidden · loading (redacted) | Spoken in words: “minus 1,600 rupees”, “20 US dollars, about 5,600 rupees”; hidden → “amount hidden”. Uses `.accessibilityLabel` built by `MoneyFormatter.spoken` |
| `MoneyField` | Big amount entry with custom keypad (“000” PKR, “.” USD, ⌫) | empty (placeholder “0”) · typing · invalid (exceeds 15 digits / 2 decimals) · disabled | Field: “Amount, 3,200 rupees”; keys: “7”, “Delete”, “Three zeros”, “Decimal point”. Also accepts hardware keyboard and paste |
| `AccountToken` | Pull-down token “HBL ▾” opening account `Menu` with balances | default · selected · USD account (shows $) · archived hidden | “Account: HBL, balance 182,400 rupees. Button, opens menu” |
| `DateToken` | “Today ▾” token → presets + compact `DatePicker` | today · past · future (scheduled) | “Date: today, 6 October” |
| `TypeToken` | “Expense ▾” — replaces segmented type control | Expense · Income · Transfer · Lend/borrow · Settle | “Type: Expense” |
| `CategoryChip` | 48 pt tile + name + parent caption, in a horizontal frequent-subcategory row (not a tab row) + “All categories…” | default · selected (solid) · suggested | “Category: Fuel, in Transport, selected” |
| `CategoryRow` / `CategoryTile` | 36 pt tile in lists | — | Tile hidden; row reads name |
| `MonogramTile` | Subscriptions/payees without logos | letter + user colour · symbol | Hidden; row reads service name |
| `BalanceCard` | Home hero: available balance, PKR+USD breakdown, rate footnote, “9 accounts” link | loaded · hidden amounts · loading · empty (no accounts → EmptyStateView) | One element: “Available balance, 484,800 rupees. 300,000 rupees plus 660 dollars at 280.” + link “9 accounts” |
| `StatCard` | Two-up cards (Budget left, Spent, Owed to you, You owe) | normal · warning line (! over) · tappable | Combined: title, value, sub-line; trait button when it navigates |
| `ProgressRing` | Budget left ring (shows **what’s left**, AUD-36) | under · near (≥ 85 % warning) · over (negative + “!”) | “Budget left, 156,626 rupees of 235,000, 33 percent used” (`.accessibilityValue`) |
| `ProgressBar` | 8 pt capsule bars (category budget, until-salary split, kameti) | under · near · over · multi-segment | Value as words; segments summarised (“Bills due take 18 % of available balance”) |
| `DueRow` | Date tile + name + when + amount (Upcoming, Calendar, Bills) | due · due today · overdue · paid ✓ · skipped (strikethrough) · estimated | “Gas bill, 3,250 rupees, overdue, was due Monday 5 October”. Swipe actions exposed as `.accessibilityActions` |
| `TransactionRow` | Activity row | expense · income · transfer · split (share line) · no movement · pending | “Office tea and snacks, minus 3,200 rupees, your share 1,600, Food › Tea & snacks, HBL” |
| `PersonAvatar` | 40 pt circle initials, person colour | default · group (stacked) · settled | Hidden when name is beside it |
| `PersonBalanceRow` | Avatar + name + “owes you / you owe / settled” | positive · negative · settled | “Usama owes you 25,000 rupees” |
| `SplitChoiceList` | Splitwise-style quick options: “You paid, split equally / Usama owes you Rs 1,600” (**green**), “You are owed the full amount” (**green**), “Usama paid, split equally / You owe Usama Rs 1,600” (**red**), “Usama is owed the full amount” (**red**); then “More options” (unequal, %, shares, multiple payers) | one selected (radio ✓) · custom | “You paid, split equally. Usama owes you 1,600 rupees. Selected, 1 of 4” |
| `SplitMemberRow` | Member with amount / % / share stepper (36 pt steppers in 44 pt hit area) | included · excluded · invalid | “Sara, 1 share, 800 rupees. Adjustable” (`.accessibilityAdjustableAction`) |
| `AssignRemainderLine` | “✓ Rs 0 left to assign” / “! Rs 400 still not assigned” | valid (positive ✓) · invalid (negative !) | Read as live region on change |
| `StatusBadge` | Pill: caption2 bold, padding 2×8, capsule, 15 % tint bg | Paid ✓ · Overdue ! · Due today · Due soon · Estimated · Paused · Skipped · Cancelled · Pending | Text is the label; symbol hidden |
| `AlertStrip` | Home overdue/over-budget strip with inline “Pay” and dismiss ✕ | overdue (negative) · over budget (warning) · backup reminder (neutral) | `.accessibilityAddTraits(.isStaticText)` + actions “Pay”, “Dismiss” |
| `ConfirmSheet` | Generic money confirmation (amount, account, date, note) + primary “Save”/“Pay”/“Settle” | editable · validating · saving (progress in button) · error | Title announces action: “Pay Gas bill” |
| `UndoToast` | “Saved · Undo” capsule, 5 s, above tab bar | showing · undone (“Undone”) · VoiceOver-held | Posts `AccessibilityNotification.Announcement("Saved. Undo available")`; does not auto-dismiss while VoiceOver focus is on it |
| `GlassTabBar` + `AddButton` | Tab bar + detached “+” | selected tab (tint, fill pill) · badge count | “Add transaction. Double-tap and hold for more types” |
| `ToolbarCircleButton` | 44 pt glass toolbar icon | default · active (filled symbol) | Required explicit label (“Ask UZee”, “Settings”, “Filter, 2 active”) |
| `FilterTokenField` | `.searchable` with tokens | empty · tokens · no results | Token: “Remove filter Shared” |
| `PrimaryButton` / `SecondaryButton` | §12 | enabled · disabled · loading · destructive | Verb + object (“Settle up with Usama”) |
| `EmptyStateView` | Wraps `ContentUnavailableView` | see §15 empty states | Title + description read; action is a button |
| `SkeletonRow` / `SkeletonCard` | Loading placeholders | shimmer · static (Reduce Motion) | Container label “Loading”; children hidden |
| `ChartDonut` | Swift Charts `SectorMark` category share | data · single slice · empty · hidden amounts (percentages only) | Summary + `AXChartDescriptor` (§16) |
| `BarChart` | Month bars with dashed limit `RuleMark` | data · partial history · over-limit bar | Summary + descriptor |
| `CalendarMonthGrid` | Month grid with day marks | today (red), selected (label fill), marks: count, ✓ paid, ! overdue, kind letter | “8 October, 2 items, 1 bill due, 1 paid” |
| `RateFootnote` | “USD at $1 = Rs 280 · edit” | default · custom rate | “US dollar converted at 280 rupees. Edit rate, button” |
| `FormRow` | Label left, value/token right, 48 pt | read · editing · error (caption below) | Label + value combined |

## 12. Buttons

| Kind | Look | SwiftUI |
|---|---|---|
| Primary | 50 pt capsule, `tint` fill, white `headline`, full width in sheets | `.buttonStyle(.glassProminent)` or `.borderedProminent` + `.controlSize(.large)` + `.buttonBorderShape(.capsule)` |
| Secondary | 50 pt capsule, `fill` bg, `tint` text | `.buttonStyle(.bordered)` / `.glass`, `.controlSize(.large)` |
| Destructive | Secondary look, `negative` text; primary red only inside `confirmationDialog` | `Button(role: .destructive)` |
| Inline action | 36 pt capsule (“Pay”, “Settle”) inside a 44 pt hit area | `.controlSize(.small)` + `.contentShape(Rectangle())` padded to 44 |
| Toolbar | 44 pt circle glass icon | `ToolbarItem` / `ToolbarCircleButton` |
| Text link | `tint` `subheadline` (“See all”, “Back up now”) ≥ 44 pt tall | `.buttonStyle(.borderless)` |
| Keypad key | 52 pt tall, no background, `fill` + scale 0.94 on press | custom `KeypadButtonStyle` |

Press feedback: `scale(0.96–0.97)` with spring 0.35 s (`PressableButtonStyle`); none under Reduce Motion. Loading: label replaced by `ProgressView()`, width kept. Disabled: system opacity plus explanatory caption.

## 13. Input fields

| Field | Spec |
|---|---|
| `MoneyField` | Hero 44 pt bold tabular; currency symbol leads in `label2`; custom keypad (3×4) below; system keyboard never shown for amounts; haptic `.selection` per key. Max 2 decimals (USD) / 0 (PKR). |
| Text field (inline in forms) | `TextField` in a `FormRow`, right-aligned value, `.body`; standalone fields: 44 pt, `fill` bg, `r.field`, focus ring = `tint` 2 pt (system focus on iPad keyboard). |
| Search | `.searchable` (system glass on iOS 26); tokens for filters; suggestions via `.searchSuggestions`. |
| Payee / note | `TextField` with `.searchSuggestions`-style list of recent payees (CAT-03); `textContentType(.none)`, autocorrect off for payees. |
| Pickers | Account, type, method, repeat, reminder lead → `Picker(.menu)` / token `Menu`. Dates → `DatePicker(.compact)`. |
| Steppers | 36 pt circles in 44 pt hit areas, `fill` bg, `tint` glyph; support `.accessibilityAdjustableAction`. |
| Toggles | System `Toggle`, default system tint. |
| Validation | Inline caption under the field in `negative` with “!” prefix; field gets `negative` 1 pt border; VoiceOver hears the error via `.accessibilityHint`. Never only a red border. |
| Keyboard | `.scrollDismissesKeyboard(.interactively)`; `@FocusState` moves payee → note → Save; hardware Return = Save when valid (iPad). |

## 14. Cards and lists

- Card: `card` fill, `r.card` 20, padding 16, no shadow, no border. Tappable cards are `Button`/`NavigationLink` with `PressableButtonStyle`.
- Card title `headline` or `footnote` semibold `label2`; value `cardValue`; sub-line `caption` `label2`.
- Lists inside cards: rows separated by 0.5 pt `sep` inset to the text start; last row no separator. For long lists (Activity, Settings) use `List` with `.listStyle(.insetGrouped)` — section corner radius is system.
- Day headers in Activity show the day’s net spend (“Rs 4,850 spent”), not item counts (AUD-03).
- Home order: AlertStrip (if any) → BalanceCard → Budget left | Spent → Until next salary → Upcoming (next 7 days) → Owed to you | You owe → Where it went + Insights → backup reminder.

## 15. States

### Success · warning · error

| State | Colour | Symbol | Words | Haptic | Where |
|---|---|---|---|---|---|
| Success | `positive` | `checkmark.circle.fill` / ✓ | “Saved”, “Paid”, “Settled”, “Backed up” | `.success` | Toast, StatusBadge, AssignRemainderLine |
| Warning | `warning` | `exclamationmark.triangle.fill` | “Due tomorrow”, “Near limit”, “Estimated” | none (or `.warning` on save of a risky value) | Badges, ProgressBar ≥ 85 % |
| Error / overdue / over | `negative` | `exclamationmark.circle.fill` / ! | “Overdue”, “Over by Rs 1,200”, “Rs 400 still not assigned” | `.error` on failed save | AlertStrip, field captions, badges |
| Blocking error | — | — | `.alert` with what happened + what to do (“Couldn’t restore. The password doesn’t match. Try again.”) | `.error` | Restore, import |
| Info | `tint` | `info.circle` | neutral explanation | none | Footnotes, onboarding |

User-facing error text comes from one place (`UserMessage` in UZeeCore errors); never show raw error descriptions.

### Empty states (from `EmptyStates.dc.html`)

`EmptyStateView` = `ContentUnavailableView { Label(title, systemImage:) } description: { Text } actions: { PrimaryButton }`. One sentence of description, one action, no illustrations.

| Context | Title | Description | Action |
|---|---|---|---|
| Home, no accounts | No accounts yet | Add the bank, wallet and USD accounts you use. Your balance and what’s due before salary appear here. | Add an account |
| Budget, none set | No budget for October | Set a monthly total and limits per category. Your spending still counts while you decide. | Set a budget |
| People | No people yet | Add someone you lend to, borrow from or split bills with. Each person gets one balance. | Add a person |
| Search, no results | `ContentUnavailableView.search(text:)` | Check the spelling, or search by payee, note, account or amount. | Clear search |
| Calendar day | Nothing due. Enjoy the day. | — | — |
| Calendar permission off | Calendar access is off | To show your iPhone calendar events next to bills and add reminders there, UZee needs Full Access. | Open Settings |
| Voice unavailable | Voice isn’t available | Speech recognition isn’t available on this iPhone right now. You can still type your question. | Use the keyboard instead |
| Microphone off | Microphone access is off | Allow UZee to use the microphone in Settings. Speech is processed on this iPhone. | Open Settings |
| Import failed | Couldn’t read this statement | The PDF may be scanned or password-protected. Nothing was imported. | Try another file |
| Import unsupported | This format isn’t supported yet | Send a sample with the amounts hidden and we’ll add support for it. Nothing was imported. | Send a sample |

### Loading states

- Target is no visible loading (PRF-01: dashboard ≤ 1.5 s from local SQLite). Show skeletons only if data takes > 300 ms; never a full-screen spinner.
- `SkeletonRow` / `SkeletonCard`: the real view with `.redacted(reason: .placeholder)` so layout doesn’t jump; shimmer 1.4 s ease-in-out using `skeleton`→`skeleton2`; **static** under Reduce Motion.
- In-button progress for saves/exports (`ProgressView()` in the button); determinate `ProgressView(value:)` for import, backup, PDF export.
- Pull-to-refresh is not used (all data local).

## 16. Charts (Swift Charts)

| Chart | Marks | Spec |
|---|---|---|
| `ChartDonut` (Where it went, Reports) | `SectorMark(angle:, innerRadius: .ratio(0.62), angularInset: 1.5)`, `.cornerRadius(3)` | Category colours from §2; max 6 slices + “Other” (grey). Legend lists **every** slice with name and %, sorted by size (AUD-17). Centre label: total spent. |
| `BarChart` (Budget drill-down, Reports months) | `BarMark` + dashed `RuleMark` for limit (`StrokeStyle(lineWidth: 1, dash: [4,3])`) | Current month bar in category colour, past months at 45 % opacity; over-limit bar gets “!” annotation, not just colour. Missing months shown as “No data” annotation, not zero bars. |
| `ProgressRing` | `Circle().trim` stroke 10 pt, round cap | Shows remaining; over-budget ring full in `negative` with “Over” text. |
| Calendar marks | text marks in 14 pt capsules | count, ✓ (paid, positive 16 %), ! (overdue, negative 14 %), kind letter; never dots-only (AUD-17). |

Rules: axes `caption2` `label2`; Y labels compact (`Rs 50k`); gridlines `sep`; no 3D, no gradients; animate on first appearance only (0.5 s spring), not on every tab switch; `chartXSelection` for scrubbing with a callout showing the exact `AmountText`. Hidden-amounts mode: charts keep shapes, values replaced with percentages; axes hidden.

VoiceOver: every chart has (1) a one-sentence `.accessibilityLabel` summary, e.g. “Dining out: September Rs 18,000, October so far Rs 11,200, limit Rs 15,000. No history for May to August.” and (2) `.accessibilityChartDescriptor(self)` implementing `AXChartDescriptorRepresentable` so Audio Graphs work. Donut summary names the top 3 categories and their shares.

## 17. Motion and haptics

Mockup curve `cubic-bezier(.2,.9,.25,1.08)` = slight overshoot → SwiftUI `.spring(duration: d, bounce: 0.15)`. Durations 0.35–0.5 s only. Tokens in `UZMotion`.

| Token | SwiftUI | Use |
|---|---|---|
| `press` | `.spring(duration: 0.35, bounce: 0.15)` | Button/card press scale 0.96 |
| `menu` | system | Menus, context menus (don’t customise) |
| `appear` | `.spring(duration: 0.4, bounce: 0.15)`, opacity 0 → 1 + offset y 12, stagger 40 ms per card, max 6 | Home cards on **first launch of the day only** |
| `sheet` | system | Sheets (0.45–0.5 s in mockups ≈ system) |
| `value` | `.spring(duration: 0.5, bounce: 0.1)` + `.contentTransition(.numericText(value:))` | Balance/total changes; ring/bar progress |
| `toast` | `.spring(duration: 0.4, bounce: 0.15)`, move from bottom + opacity | UndoToast in/out |
| `selection` | `.spring(duration: 0.35, bounce: 0.2)` | Category chip select, calendar day select (scale 0.88 on press) |

Rules: no count-up on every open (AUD-37) — numbers roll only when the value changes; no looping animations except skeleton shimmer; `matchedGeometryEffect` / `.navigationTransition(.zoom)` only for card → detail on iPad if it stays ≤ 0.5 s.

**Reduce Motion** (`@Environment(\.accessibilityReduceMotion)`): no appear offsets or stagger (content just shows), no press scale, numeric transitions become `.identity` (instant), shimmer static, chart appear animation off, crossfade (`.opacity`, 0.2 s) replaces any movement. Mockups already do this via `prefers-reduced-motion`.

Haptics (`.sensoryFeedback`):

| Moment | Feedback |
|---|---|
| Money saved / paid / settled | `.success` |
| Undo tapped | `.impact(weight: .light)` |
| Validation blocks Save | `.error` |
| Keypad key | `.selection` (system respects “System Haptics” off) |
| Menu/token/category/day selection | `.selection` |
| Swipe action committed | `.impact(weight: .medium)` |
| Over-budget crossed by this entry | `.warning` |

## 18. Accessibility

| Area | Rule |
|---|---|
| Targets | ≥ 44×44 pt for every control (`.frame(minWidth: 44, minHeight: 44)` + `.contentShape`); visual can be smaller (36 pt “Pay”, steppers). |
| Dynamic Type | All text uses text styles / `@ScaledMetric`; test xSmall → AX5. Use `@Environment(\.dynamicTypeSize)`; when `.isAccessibilitySize`: two-up card grids become one column; row amounts move under the title (`ViewThatFits` / `AnyLayout(VStackLayout)` vs `HStackLayout`); category chip row becomes a vertical list; keypad keeps size but sheet goes `.large`; tab bar labels are system-handled (Large Content Viewer via `.accessibilityShowsLargeContentViewer()` on custom tab/“+” controls). Hero amount scales but caps at `.accessibility3` (`.dynamicTypeSize(...DynamicTypeSize.accessibility3)`) only for the 44 pt hero to avoid wrapping digits. |
| VoiceOver | Each row/card is one element (`.accessibilityElement(children: .combine)`) with a label built in this order: **name, amount (spoken), direction/status, meta**. Decorative tiles/avatars hidden. Custom controls declare traits (`.isButton`, `.isSelected`, `.isHeader`). Swipe and context actions exposed via `.accessibilityActions`. Toast and validation changes announced. |
| Colour | Never the only signal (A11Y-03): words (“owes you”, “Overdue”) or symbols (✓ ! clock) always accompany colour. Text contrast ≥ 4.5:1 (that’s why `label2`, `positive`, `negative`, `warning` use the darker light-mode values); graphics ≥ 3:1. |
| Reduce Motion / Transparency / Increase Contrast / Bold Text / Smart Invert | Honoured (§7, §17); images and category tiles marked `.accessibilityIgnoresInvertColors()` only where needed (receipts). |
| Charts | Summary label + `AXChartDescriptorRepresentable` (§16). |
| Money spoken | `MoneyFormatter.spoken`: “25,000 rupees”, “20 US dollars, about 5,600 rupees”, “minus”, never “R S”. |
| Hide amounts | VoiceOver reads “amount hidden”; no value leaks via `accessibilityValue`. |
| Labels in UI tests | Every interactive component gets a stable `accessibilityIdentifier` (`home.balanceCard`, `add.save`) used by XCTest smoke tests. |

## 19. Light and dark mode

- Both are first-class (NFR-04). All colours come from §1/§2 tokens, which carry both appearances; feature code never checks `colorScheme` for colours.
- Dark mode uses true black `bg` (#000) with elevated `card` #1C1C1E and `card2` #2C2C2E — elevation by lightness, not shadow.
- Status colours switch to the brighter system dark values (#30D158 / #FF453A / #FF9F0A); category glyphs use the dark system colour; Utilities text/glyph switches from #A07800 to #FFCC00.
- Glass adapts automatically; custom tinted surfaces (toast) stay dark in both modes.
- Previews: every component has `#Preview` in light, dark, AX3 and RTL-safe (no hard-coded left/right — use leading/trailing).
- Snapshot tests cover Home, Add, Activity, Calendar in light and dark with the sample dataset.

## 20. iPad adaptations (NFR-02, AUD-34)

| Area | iPad behaviour |
|---|---|
| Root | `NavigationSplitView` with a glass sidebar: Home, Activity, Budget, Calendar, People, Reports, Bills & subscriptions, Accounts, Settings. Sidebar hide/show via toolbar button; `columnVisibility` remembered. Compact width (Slide Over, narrow Split View) falls back to the iPhone `TabView` automatically via `horizontalSizeClass`. |
| Columns | Activity and People: list + detail (three-column for People → Person → transaction). Calendar: month grid with day detail column on the side. Budget: categories + drill-down chart. |
| Home | `Grid` 3 columns in landscape / 2 in portrait; BalanceCard and AlertStrip span all columns; gutter 20, card gap 16, card padding 18–20. |
| Max widths | Reading content max 680 pt (forms, detail screens) centred in wide columns. |
| Modals | Add, Confirm, Split: `.presentationSizing(.form)`; pickers and menus as popovers; `confirmationDialog` becomes a popover anchored to its button. Save shows Undo toast at the bottom of the detail column. |
| Input | Full keyboard support: ⌘N new expense, ⌘⇧T transfer, ⌘F search, ⌘, Settings, Return = Save, Esc = Cancel (`.keyboardShortcut`). Number row types into `MoneyField`. Pointer hover effects (`.hoverEffect(.highlight)`) on rows and cards. |
| Drag & drop | Receipts (images/PDF) droppable onto a transaction detail; statement PDFs onto Import. |
| Multitasking | Layout responds to size class, not device; tested in ½ and ⅓ Split View and Stage Manager windows. |

## 21. Do / don’t checklist (review gate for every screen)

| Do | Don’t |
|---|---|
| Use tokens, text styles, `AmountText` | Raw hex, fixed font sizes, inline money formatting |
| Title menus, toolbar menus, pull-down tokens | Segmented controls or chip-row tabs at the top of a screen |
| Confirm money actions, then “Saved · Undo” toast (5 s) | One-tap saves, toasts without Undo |
| Words + colour for owed/owe and status | Green/red numbers alone |
| Monogram or SF Symbol for services | Brand logos |
| Currency symbol on every amount, `≈ Rs` for USD, rate footnote on mixed totals | Bare numbers, USD without PKR equivalent |
| System components (List, Menu, sheets, ContentUnavailableView, Swift Charts) | Hand-built replacements for system controls |
| 44 pt targets, AX5 layouts, VoiceOver chart summaries | Dots-only calendar marks, truncated amounts |
| Springs 0.35–0.5 s, Reduce Motion fallbacks | Long count-ups on every open, looping decoration |
