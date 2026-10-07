# UZee — PROJECT_STATE

Last updated: 2026-10-06

- **CURRENT VERSION:** 0.0.1 (1), installed on owner's iPhone 2026-10-06
- **CURRENT STAGE:** Milestone 0 (Foundation) complete: CI green on iPhone + iPad simulators (run #5), app installed and launched on owner's iPhone ("Database ready"). Waiting for owner's "go" to start Milestone 1. Mockups: https://claude.ai/artifact/HJYyNRvfiwhBdWfncFRpmj
- **CURRENT MILESTONE:** M0 done; M1 next (docs/MILESTONE_PLAN.md)
- **COMPLETED STAGES:** Requirement Discovery (docs/DISCOVERY.md)
- **CURRENT ARCHITECTURE:** not yet defined. Direction from discovery: native SwiftUI universal iPhone + iPad app, iOS 26+, on-device storage, Apple Foundation Models for AI, built on the user's M1 Mac
- **IMPORTANT DECISIONS:** see docs/DISCOVERY.md (answer tables per group). Key: personal use; PKR base + USD (1 USD = 280 PKR fixed for now); transfers are not spending; calendar-month budgets with category limits; separate Office section with 50/50 partner settlement; kameti type; reminders configurable; iOS Calendar export; optional Face ID; manual encrypted backup in v1, cloud sync later; PDF statement import; CSV + PDF export; receipts; 30-day Recently Deleted; English voice assistant via "Hey Siri, ask UZee" + in-app mic
- **OPEN BUGS:** none
- **KNOWN ISSUES:** none
- **PENDING USER DECISIONS / INPUTS:**
  - Run the REQUIRED NOW steps in docs/PREREQUISITES.md and paste the verification output
  - Kameti figures (240k paid vs 300k payouts)
  - Sample bank statement PDFs (one per bank) before the import milestone
- **ENVIRONMENT:** REQUIRED NOW complete (2026-10-06): macOS 27.0, Xcode 27.0 beta, Swift 6.4, iOS 26.5 + 27.0 simulators, git user iTech, gh logged in as iumer, 16 GiB free. iPhone 17 Pro Max iOS 27 paired, Developer Mode on, Apple ID in Xcode (2026-10-06); ~12 GB free on Mac
- **NEXT TASK:** On owner's "go": create `main` from this branch and tag v0.0.1, then start M1 per docs/MILESTONE_PLAN.md. Install route: owner pulls branch in ~/Uzee and presses Run in Xcode 27 beta (Personal Team); the Mac Remote Control session can do this for them
- **BUILD ROUTE:** decided 2026-10-05: cloud-written code + GitHub Actions macOS CI for build/tests; user pulls code and installs to iPhone from local Xcode (free Apple ID, 7-day re-install). TestFlight later with paid account
- **TOTAL TESTS:** 313 registered (docs/TEST_REGISTRY.md) · **RUN:** 10 · **PASSING:** 10 (3 partial) · **FAILING:** 0
