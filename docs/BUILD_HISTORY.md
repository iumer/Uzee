# UZee — Build History

| | |
|---|---|
| Version | 0.1 (2026-10-06) |
| Latest build | 0.0.1 (1), 2026-10-06 |
| Related | MILESTONE_PLAN.md, TEST_PLAN.md §6 and §9, BUG_REGISTRY.md, DEPLOYMENT_GUIDE.md |

## Rules (master prompt §16, §17)

- Every distributable build has a unique **version** `0.MILESTONE.PATCH` (marketing version) and a unique, ever-increasing **build number** (`CFBundleVersion`: 1, 2, 3 … never reset). Example: `0.2.1 (15)`.
- Milestone *N* ships `0.N.0`; fixes inside it ship `0.N.1`, `0.N.2` … M0 ships `0.0.1`. Version 1.0.0 is the first release after M12.
- A build is never called ready without its test status. Every entry is written **after** the test-before-build gate (TEST_PLAN §6) and reports failures openly.
- Each build is tagged in git (`v0.N.P`) on the commit it was built from; the tag is the rollback point.
- Newest entry on top.

## Summary

| Version (build) | Date | Milestone | Highlights | Tests run / pass / fail | Installed on |
|---|---|---|---|---|---|
| 0.0.1 (1) | 2026-10-06 | M0 — Foundation | Xcode project, 4 packages, GRDB database, CI, launch screen | 10 run / 10 pass (3 partial) / 0 fail | Owner's iPhone 17 Pro Max (iOS 27.0) |

## Entry format

```
BUILD:               0.N.P (build number)
DATE:                YYYY-MM-DD
MILESTONE:           MN — name
GIT:                 tag v0.N.P · commit <sha> · branch
NEW FEATURES:
CHANGES:
BUG FIXES:           BUG-nnn …
KNOWN ISSUES:        (with severity; owner approval if shipping with them)
NEW TESTS:           IDs added to TEST_REGISTRY
TESTS RUN:           suites + where (CI core-linux #, CI ios #, simulator models, owner's iPhone manual)
PASS:
FAIL:                each failed ID with expected / actual / likely reason / severity / blocks build?
NOT RUN:             each ID and why
REGRESSIONS:         previously passing tests now failing (none / list)
INSTALLATION NOTES:  how to install (DEPLOYMENT_GUIDE §2), schema migration (yes/no, safety copy), 7-day expiry date for free-Apple-ID installs, backup advice
```

## Builds

```
BUILD:               0.0.1 (1)
DATE:                2026-10-06
MILESTONE:           M0 — Foundation
GIT:                 commit b987435 · branch claude/project-thread-m75ycs (tag v0.0.1 to be added when main exists)
NEW FEATURES:        Launch screen showing app name, version "0.0.1 (1)" and database status
CHANGES:             Xcode project (universal iPhone + iPad, iOS 26+); local packages UZeeCore, UZeeData (GRDB 7,
                     migration v1_baseline), UZeeSystem (logging), UZeeUI; xcconfig versioning; CI (Linux core tests,
                     secret check, iOS package tests + smoke UI tests on iPhone and iPad simulators); scripts
BUG FIXES:           none (pre-release CI fixes only: SMK-004 duplicate accessibility match, iPad simulator boot timeout)
KNOWN ISSUES:        none in the app. CI runs Xcode 26.6 / iOS 26.5 simulators (newest on the runner); owner builds
                     with Xcode 27 beta / iOS 27 — both green.
NEW TESTS:           AppInfoTests (2), MigrationTests (3), LogTests (1), LaunchViewTests (1), SmokeTests (4)
TESTS RUN:           CI run #5 (37542793190): core-linux, secret check, package tests on iPhone 17 Pro sim,
                     smoke UI tests on iPhone 17 Pro and iPad Pro 13-inch (M5) sims, iOS 26.5.
                     Manual: install + launch on owner's iPhone 17 Pro Max, iOS 27.0, Xcode 27 beta.
PASS:                SMK-001, SMK-002, ENV-001, ENV-002, ENV-004, ENV-006, ENV-007
                     Partial pass: SMK-003 (1 cold launch, not 5), SMK-004 (in-memory DB; file/WAL/protection not
                     inspected), SMK-011 (1 relaunch cycle, no background/foreground)
FAIL:                none
NOT RUN:             ENV-003 (⌘U on owner's Mac; build + run done), ENV-005 (file protection on device, needs debug
                     screen), ENV-008 (logger redaction in Console)
REGRESSIONS:         none (first build)
INSTALLATION NOTES:  DEPLOYMENT_GUIDE §2: open UZee.xcodeproj, Team = Personal Team, run on iPhone, trust the
                     developer once. No user data yet; migration v1 creates an empty settings table.
                     Free Apple ID: app stops opening after 7 days (around 2026-10-13); press Run again to renew.
```
