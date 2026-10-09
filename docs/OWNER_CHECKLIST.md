# UZee — Owner checklist (every request and bug, rechecked each build)

Every change the owner asked for and every bug they reported. Before each new build, each row is checked again
so fixing one thing can't quietly break another. **Auto** = a test runs it on every Mac build (smoke test or unit
test named in the row). **Phone** = checked by hand on the iPhone, because a test can't do it (Face ID, camera,
microphone, real voices, live network).

Status per build goes in the last column: ✓ passed, ✗ broke (then it becomes a bug below), – not checked yet.

## Requests

| ID | Asked | What must be true | How it's checked | 0.11.2 |
|---|---|---|---|---|
| OWN-001 | 2026-10-07 | Pick a bank and type its balance in first-launch setup | Phone | – |
| OWN-002 | 2026-10-07 | Saving an expense saves straight away (no extra confirm screen) | Auto: SMK007 | – |
| OWN-003 | 2026-10-08 | "I owe my mom 250000" said to UZee records a debt | Auto: VoiceTests (Core) | – |
| OWN-004 | 2026-10-08 | Owe/owed amounts are green (they owe you) and red (you owe); "They paid you 50k of 150k" lowers the balance | Auto: LOAN-009 (Data), OWN004 smoke; Phone for colours | – |
| OWN-005 | 2026-10-08 | Home mic is the singing UZee smiley | Phone | – |
| OWN-006 | 2026-10-08 | Ask UZee opens for talking with no text box; a keyboard button switches to typing | Auto: OWN006 smoke | – |
| OWN-007 | 2026-10-08 | Opening Ask UZee shows UZee asleep, then waking up to listen | Phone | – |
| OWN-008 | 2026-10-08 | USD→PKR comes live from Wise; past-dated transfers use Wise's rate that day; offline uses the saved rate and says so | Auto: WiseRatesTests (Core), WiseRateFetcherTests (Mac, online); Phone | – |
| OWN-009 | 2026-10-08 | Settings › UZee's voice lists natural voices first, with a speed slider | Auto: OWN009 smoke; Phone for sound | – |
| OWN-010 | 2026-10-08 | Lock screen has "Use iPhone passcode" | Phone | – |
| OWN-011 | 2026-10-08 | Settings › Erase everything | Auto: OWN011 smoke | – |
| OWN-012 | 2026-10-08 | Voice picker for Siri-style answers | Phone | – |
| OWN-013 | 2026-10-08 | Saved voice chats (New chat / Past chats) | Phone | – |
| OWN-014 | 2026-10-08 | Receipt scan reads the total right on most printed slips | Auto: InternetReceiptTests (Mac, 30 SROIE receipts, ≥ 80%) | – |
| OWN-015 | 2026-10-08 | System / Light / Dark theme | Phone | – |
| OWN-016 | 2026-10-08 | App is named "UZee" on the Home Screen (not "UZee Dev") | Phone | – |
| OWN-017 | 2026-10-09 | Namaz times work offline; if location fails you can pick your city | Auto: PrayerTests (Core); Phone | – |
| OWN-018 | 2026-10-07 | Statement PDFs from MCB, HBL, Meezan, SadaPay, NayaPay and Wise import | Auto: StatementLayoutTests (Core, synthetic rows) | – |

## Bugs

| ID | Reported | Bug | Root cause | Regression check | Fixed in | Status |
|---|---|---|---|---|---|---|
| BUG-001 | 2026-10-07 | Sample data failed when a real account had the same name ("Hbl" vs "HBL") | Sample account names clashed with real ones (migration v8) | SampleDataTests | 0.6.1 (8) | Verified |
| BUG-002 | 2026-10-08 | Saving an Ask UZee card crashed | See commit 9b772e8 | Auto: VOX007 smoke | 9b772e8 | Verified |
| BUG-003 | 2026-10-08 | Close on the Add sheet sometimes didn't close it | See commit 08e2efc | Auto: UI034 smoke | 08e2efc | Verified |
| BUG-004 | 2026-10-08 | "Use iPhone passcode" opened Face ID | It called the same Face ID check as Unlock | Phone (Face ID can't be tested automatically) | 46b8e36 | Fixed, check on phone |
| BUG-005 | 2026-10-09 | Calendar missing the 1st–6th of every month | Grid cells shared ids with the weekday letters, so the grid dropped them | Auto: CAL001 smoke checks days 1–6 | 0.11.1 | Fixed, check on phone |

## Waiting on the owner

- Simpler Add expense form (mockup boards A and B): build after OK.
- Simpler app (new Home, one top bar on every tab, budget "can I buy this?", Apple Intelligence on/off): mockups first, build after OK.
