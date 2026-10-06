# UZee — Bug Registry

| | |
|---|---|
| Version | 0.1 (2026-10-06) |
| Open bugs | 0 (Critical 0 · High 0 · Medium 0 · Low 0) |
| Related | TEST_REGISTRY.md (REG tests), BUILD_HISTORY.md, TEST_PLAN.md §6 |

## Policy (master prompt §15 — mandatory)

When the owner (or a test) reports a bug:

| Step | Action | Recorded in |
|---|---|---|
| 1 | Reproduce or analyse the issue (exact steps, build, device, data) | Entry below |
| 2 | Assign the next `BUG-nnn` id (never reused) | Entry below |
| 3 | Find and write the **root cause** (not the symptom) | Entry below |
| 4 | Write a permanent regression test `REG-nnn` that fails on the current code | TEST_REGISTRY §18 (full format) |
| 5 | Fix on `feature/bug-nnn-<topic>` (or `hotfix/…` from `main` for a released build) | Commit `fix: … (BUG-nnn)` |
| 6 | Run the new REG test → must pass | Entry below |
| 7 | Run the affected module's tests | Entry below |
| 8 | Run smoke tests | Entry below |
| 9 | Run the full REG suite | Entry below |
| 10 | Only then produce a new build (PATCH version bump), with results in BUILD_HISTORY | BUILD_HISTORY |

A bug is **Fixed** only when: root cause identified + fix implemented + regression test created + test passes + related tests pass. A code change alone is not a fix. REG tests are never removed; they run before every build (TEST_PLAN §6).

**Severity**: Critical = wrong money/balance, data loss or corruption, crash on launch, security/privacy leak · High = core flow blocked, wrong reminder date, wrong total on a screen · Medium = wrong display or format with a workaround · Low = cosmetic.
Critical and High block builds unless the owner explicitly approves shipping with a known issue (recorded in the entry and PROJECT_STATE).

**Status values**: `New` → `Confirmed` → `In progress` → `Fixed (pending verification)` → `Verified` (owner confirmed on device) · or `Won't fix` / `Not a bug` / `Duplicate of BUG-nnn` with reason.

## Entry format

```
BUG ID:          BUG-nnn
TITLE:
REPORTED:        date · by (owner / test id)
BUILD FOUND:     0.N.P (build)
DEVICE / OS:
MODULE:
SEVERITY:
STEPS TO REPRODUCE:
EXPECTED:
ACTUAL:
ROOT CAUSE:
FIX:             commit / branch
REGRESSION TEST: REG-nnn
TESTS RUN:       REG-nnn · module tests · smoke · full REG suite — pass/fail counts
FIXED IN BUILD:  0.N.P (build)
STATUS:
NOTES:
```

## Register

| Bug ID | Title | Module | Severity | Found in | Root cause | Regression test | Fixed in | Status |
|---|---|---|---|---|---|---|---|---|
| — | No bugs reported yet | — | — | — | — | — | — | — |

## Entries

None yet.
