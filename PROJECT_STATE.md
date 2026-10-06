# UZee — PROJECT_STATE

Last updated: 2026-10-06

- **CURRENT VERSION:** none (no application code yet)
- **CURRENT STAGE:** Design approved 2026-10-06 (user: "use your recommended for all and start with next steps"). Now writing design system, screen inventory, architecture, data model, milestone plan and test strategy. Mockups (UX baseline): https://claude.ai/artifact/HJYyNRvfiwhBdWfncFRpmj
- **CURRENT MILESTONE:** none (implementation not started)
- **COMPLETED STAGES:** Requirement Discovery (docs/DISCOVERY.md)
- **CURRENT ARCHITECTURE:** not yet defined. Direction from discovery: native SwiftUI universal iPhone + iPad app, iOS 26+, on-device storage, Apple Foundation Models for AI, built on the user's M1 Mac
- **IMPORTANT DECISIONS:** see docs/DISCOVERY.md (answer tables per group). Key: personal use; PKR base + USD (1 USD = 280 PKR fixed for now); transfers are not spending; calendar-month budgets with category limits; separate Office section with 50/50 partner settlement; kameti type; reminders configurable; iOS Calendar export; optional Face ID; manual encrypted backup in v1, cloud sync later; PDF statement import; CSV + PDF export; receipts; 30-day Recently Deleted; English voice assistant via "Hey Siri, ask UZee" + in-app mic
- **OPEN BUGS:** none
- **KNOWN ISSUES:** none
- **PENDING USER DECISIONS / INPUTS:**
  - Run the REQUIRED NOW steps in docs/PREREQUISITES.md and paste the verification output
  - Kameti figures (240k paid vs 300k payouts)
  - Sample bank statement PDFs (one per bank) before the import milestone
- **ENVIRONMENT:** REQUIRED NOW complete (2026-10-06): macOS 27.0, Xcode 27.0 beta, Swift 6.4, iOS 26.5 + 27.0 simulators, git user iTech, gh logged in as iumer, 16 GiB free. iPhone 17 Pro Max iOS 27 not paired yet (REQUIRED LATER)
- **NEXT TASK:** Finish post-design docs, then ask the user for explicit approval to start Milestone 0 (project skeleton). Final UX calls: Calendar opens Bills & subscriptions from a toolbar list button; People tab is a people-only list with groups behind a Groups button; Splitwise four quick split options; onboarding lets the user pick base currency and add any bank with its own currency
- **BUILD ROUTE:** decided 2026-10-05: cloud-written code + GitHub Actions macOS CI for build/tests; user pulls code and installs to iPhone from local Xcode (free Apple ID, 7-day re-install). TestFlight later with paid account
- **TOTAL TESTS:** 0 · **PASSING:** 0 · **FAILING:** 0
