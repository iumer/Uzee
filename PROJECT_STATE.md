# UZee — PROJECT_STATE

Last updated: 2026-10-07

- **CURRENT VERSION:** 0.1.0 (2), installed on owner's iPhone 17 Pro Max (iOS 27) 2026-10-07; free Apple ID, reinstall within 7 days
- **CURRENT STAGE:** Milestone 1 (navigation shell & design system) approved by owner 2026-10-07: iPhone smoke tests 9/9 in CI run #13 and on owner's Mac; iPad smoke not completed (UI-004 not run). Milestone 2 (accounts and money engine) in progress. Mockups: https://claude.ai/artifact/HJYyNRvfiwhBdWfncFRpmj
- **CURRENT MILESTONE:** M2 (docs/MILESTONE_PLAN.md); M0 and M1 done
- **COMPLETED STAGES:** Requirement Discovery (docs/DISCOVERY.md); design approval and planning docs (2026-10-06); M0 Foundation 0.0.1 (1); M1 Navigation shell & design system 0.1.0 (2)
- **CURRENT ARCHITECTURE:** docs/ARCHITECTURE.md and docs/tech-decisions-brief.md: native SwiftUI universal iPhone + iPad app, iOS 26+, GRDB/SQLite on device, packages UZeeCore/UZeeData/UZeeSystem/UZeeUI, Apple Foundation Models for AI
- **IMPORTANT DECISIONS:** see docs/DISCOVERY.md (answer tables per group). Key: personal use; PKR base + USD (1 USD = 280 PKR fixed for now); transfers are not spending; calendar-month budgets with category limits; Splitwise-style people and groups, office is one group (replaced the Office section with 50/50 settlement, 2026-10-06); kameti type; reminders configurable; iOS Calendar export; optional Face ID; manual encrypted backup in v1, cloud sync later; PDF statement import; CSV + PDF export; receipts; 30-day Recently Deleted; English voice assistant via "Hey Siri, ask UZee" + in-app mic
- **OPEN BUGS:** none
- **KNOWN ISSUES:** iPad not tested in 0.1.0 (2): iPad smoke run did not complete (UI-004 not run); CI workflow fixed
- **PENDING USER DECISIONS / INPUTS:**
  - Kameti figures (240k paid vs 300k payouts)
  - Sample bank statement PDFs (one per bank) before the import milestone
- **ENVIRONMENT:** REQUIRED NOW complete (2026-10-06): macOS 27.0, Xcode 27.0 beta, Swift 6.4, iOS 26.5 + 27.0 simulators, git user iTech, gh logged in as iumer, 16 GiB free. iPhone 17 Pro Max iOS 27 paired, Developer Mode on, Apple ID in Xcode (2026-10-06); ~12 GB free on Mac
- **NEXT TASK:** Finish M2 per docs/MILESTONE_PLAN.md. Daily tests on owner's Mac simulator via the Remote Control session; full GitHub iPhone + iPad run once per milestone by manual dispatch. Install route: owner pulls branch in ~/Uzee and presses Run in Xcode 27 beta (Personal Team)
- **BUILD ROUTE:** decided 2026-10-05: cloud-written code + GitHub Actions CI; user pulls code and installs to iPhone from local Xcode (free Apple ID, 7-day re-install). TestFlight later with paid account. CI policy from 2026-10-07: pushes run Linux checks (~1–3 min); the GitHub Mac simulator job (20–45 min) runs only on manual runs and on `main`; day-to-day UI tests on owner's Mac (~4 min). Branches: `main` created 2026-10-07 at 4fba7f0 (M0 build); work on claude/project-thread-m75ycs. Tags v0.0.1 and v0.1.0 not pushed (proxy blocks tag pushes)
- **TOTAL TESTS:** 313 registered (docs/TEST_REGISTRY.md) · **RUN:** 21 · **PASSING:** 21 (6 partial) · **FAILING:** 0
