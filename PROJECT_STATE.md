# UZee — PROJECT_STATE

Last updated: 2026-10-06

- **CURRENT VERSION:** none (no application code yet)
- **CURRENT STAGE:** Post-design docs complete (design system, screen inventory, architecture, data model, milestone plan, test plan + registry of 313 tests, bug registry, build history, changelog, deployment guide). Waiting for explicit approval to start Milestone 0. Mockups: https://claude.ai/artifact/HJYyNRvfiwhBdWfncFRpmj
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
- **NEXT TASK:** On approval, start M0 per docs/MILESTONE_PLAN.md: create main + development branches, Xcode project with local packages, GRDB, CI, smoke tests, build 0.0.1 (1). Defaults settled in docs/tech-decisions-brief.md
- **BUILD ROUTE:** decided 2026-10-05: cloud-written code + GitHub Actions macOS CI for build/tests; user pulls code and installs to iPhone from local Xcode (free Apple ID, 7-day re-install). TestFlight later with paid account
- **TOTAL TESTS:** 313 registered (docs/TEST_REGISTRY.md) · **RUN:** 0 · **PASSING:** 0 · **FAILING:** 0
