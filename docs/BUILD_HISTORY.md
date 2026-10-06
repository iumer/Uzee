# UZee — Build History

| | |
|---|---|
| Version | 0.1 (2026-10-06) |
| Latest build | none (no application code yet) |
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
| — | — | — | No builds yet | — | — |

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

None yet. The first planned build is **0.0.1 (1)** at the end of Milestone 0.
