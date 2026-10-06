# UZee — Deployment Guide

| | |
|---|---|
| Version | 0.1 (2026-10-06) |
| Current route | Free Apple ID, install from the owner's Mac (7-day builds) |
| Later route | TestFlight / App Store with the paid Apple Developer Program (M12) |
| Related | PREREQUISITES.md, BUILD_HISTORY.md, MILESTONE_PLAN.md (M0, M12), TEST_PLAN.md §6 |

Nothing in this guide is done without the test-before-build gate (TEST_PLAN §6) and a BUILD_HISTORY entry. TestFlight and App Store steps run only after the owner's explicit approval (master prompt §30).

## 1. Environment

| Item | Value |
|---|---|
| Mac | MacBook Pro M1, macOS 27.0 |
| Xcode | 27.0 beta at `/Applications/Xcode-beta.app` (local builds). A **release** Xcode is required for App Store Connect uploads (§3) |
| Device | iPhone 17 Pro Max, iOS 27, Apple Intelligence on |
| Repository | `github.com/iumer/Uzee` — `main` stable, `development` integration, `feature/*` work |
| App | Universal iPhone + iPad, iOS 26.0 minimum, bundle id `com.<you>.uzee` (Release) and `com.<you>.uzee.dev` (Debug, "UZee Dev"); final value fixed in M0 and never changed afterwards, or on-device data is lost |

## 2. Install now: free Apple ID, from the owner's Mac

All commands run in **Terminal on the Mac** unless a step says **iPhone**.

### 2.1 One-time setup

| # | Where | Step | Check |
|---|---|---|---|
| 1 | Mac | Make the beta Xcode active: `sudo xcode-select -s /Applications/Xcode-beta.app/Contents/Developer` | `xcodebuild -version` shows Xcode 27.0 |
| 2 | Mac | Xcode → Settings → Accounts → **+** → Apple ID → sign in with your normal Apple ID | A team "*Your Name* (Personal Team)" appears |
| 3 | iPhone | Settings → General → About: iOS 26.0 or newer (you have iOS 27) | — |
| 4 | iPhone | Connect to the Mac with a USB-C cable, unlock, tap **Trust**, enter passcode | — |
| 5 | Mac | Xcode → Window → Devices and Simulators → select the iPhone; wait for "Preparing device…/copying shared cache" to finish (can take several minutes, uses ~2–4 GB) | Phone listed without warnings |
| 6 | iPhone | Settings → Privacy & Security → **Developer Mode** → On → Restart → after restart tap **Turn On** and enter passcode. (The switch appears only after step 4–5.) | — |
| 7 | Mac | `xcrun devicectl list devices` | iPhone shows `available (paired)` |
| 8 | Mac (optional) | Devices and Simulators → tick **Connect via network** for wireless installs (same Wi-Fi) | Globe icon next to the phone |

### 2.2 Get the code

```bash
cd ~/Developer                       # or any folder you prefer
gh repo clone iumer/Uzee             # first time only
cd Uzee
git fetch --tags
git checkout v0.0.1                  # the build named in BUILD_HISTORY (or: git switch development && git pull)
open UZee.xcodeproj
```

### 2.3 Sign and run

| # | Where | Step |
|---|---|---|
| 1 | Xcode | Select project **UZee** → target **UZee** → **Signing & Capabilities** |
| 2 | Xcode | Tick **Automatically manage signing**; Team = *Your Name (Personal Team)* |
| 3 | Xcode | Bundle Identifier = the value fixed in M0 (`com.<you>.uzee`). If Xcode says it's unavailable, pick a unique one once and keep it forever |
| 4 | Xcode | Toolbar run destination → your iPhone. For the **daily-use install** choose Product → Scheme → Edit Scheme → Run → Build Configuration **Release** (bundle id `…uzee`, real data). Debug builds install separately as "UZee Dev" (`…uzee.dev`, ARCHITECTURE build configurations), so test data never mixes with real data |
| 5 | Xcode | Product → **Run** (⌘R). First time Xcode may ask for your Mac login password for the keychain → **Always Allow** |
| 6 | iPhone | First launch only: "Untrusted Developer" → Settings → General → **VPN & Device Management** → *Apple Development: your Apple ID* → **Trust** → open UZee again |
| 7 | iPhone | Run the manual checks for this build (SMK-001…003, SMK-011 and the milestone's Level M tests) and report results in the thread |

Command-line alternative (same result, after one successful run from Xcode):

```bash
xcodebuild -project UZee.xcodeproj -scheme UZee -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build -allowProvisioningUpdates build
xcrun devicectl device install app --device <iPhone name or id from devicectl list> \
  build/Build/Products/Release-iphoneos/UZee.app
```

### 2.4 The 7-day limit (free Apple ID)

| Fact | What to do |
|---|---|
| Free provisioning profiles expire **7 days** after the install; the app then won't open | Re-run from Xcode (§2.3 step 4–5) **before** day 7. Each BUILD_HISTORY entry states the expiry date |
| Re-running with the **same bundle id** keeps all data | Never delete the app to "fix" an install — that deletes the data. Never change the bundle id |
| If the app already expired | Just run from Xcode again; data is still there |
| Max 3 free-signed apps per device; ~10 new app ids per 7 days | Keep only UZee installed this way |
| Some capabilities need the paid program (iCloud/CloudKit, push; Siri entitlement possibly) | Verified in the M0 device spike; App Intents/App Shortcuts are designed not to need the paid account. Findings go to PROJECT_STATE |
| Personal data on the phone is the only copy until backups exist (M10) | From M10 on: Settings → Backup before every reinstall of a new version |

### 2.5 Updating to a newer build

1. Read the BUILD_HISTORY entry (tests, known issues, migration yes/no).
2. From M10: make an encrypted backup in UZee and save it to Files/iCloud Drive.
3. `git fetch --tags && git checkout v0.N.P`, then Run from Xcode over the existing app (do not delete it).
4. The app migrates the database on first launch and keeps a pre-migration safety copy (DATA-05).

## 3. Later: TestFlight and App Store (M12, paid account, owner approval)

| §30 item | Plan for UZee |
|---|---|
| Prerequisites | Apple Developer Program ($99/year) enrolled with the owner's Apple ID; **release** (non-beta) Xcode installed for uploads |
| App identifier | Explicit App ID = the bundle id fixed in M0, registered at developer.apple.com → Identifiers. Capabilities only as needed (App Intents/Siri if required; iCloud only when sync is built) |
| Certificates | **Apple Distribution** certificate created and kept by Xcode (automatic signing). Never exported to the repo |
| Provisioning | Xcode-managed App Store provisioning profile |
| Production build | Scheme UZee, configuration **Release**: Product → Archive → Organizer. Release build has no debug menu, sample data off by default, logging at default level with privacy redaction |
| Production configuration | `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` from the xcconfig; build number higher than any previous upload; deployment target iOS 26.0 |
| Versioning | 1.0.0 for the first release; TestFlight builds may be 0.12.x; build numbers continue the same sequence as BUILD_HISTORY |
| TestFlight | App Store Connect → My Apps → **+** New App (name UZee, bundle id, SKU, primary language English). Organizer → Distribute App → App Store Connect → Upload. Internal testing first (owner); external testers need Beta App Review |
| Export compliance | Answer the encryption question at upload: UZee uses only Apple's built-in encryption (Data Protection, CryptoKit for backups); confirm the exemption wording at that time and set `ITSAppUsesNonExemptEncryption` accordingly |
| Privacy information | App Privacy: **Data Not Collected** (no network, no analytics, PRV-01/02). Privacy manifest `PrivacyInfo.xcprivacy` listing required-reason APIs used (e.g. UserDefaults, file timestamps). Usage descriptions for Face ID, notifications, calendars, camera, photos, Siri, speech, microphone |
| Store metadata | Name, subtitle, description, keywords, category Finance, support URL, privacy policy URL (simple page stating no data leaves the device), age rating |
| Screenshots | From the simulator with sample data: iPhone 6.9" and iPad 13" (light; dark optional); sample-data banner hidden for screenshots only via a screenshot launch argument |
| Release notes | From CHANGELOG for the version ("What to Test" for TestFlight) |
| Backup considerations | Before release: DATA-020…026 pass; release notes remind users to make a backup; migrations always keep a safety copy |
| Approval gate | Release Readiness Report (REL-001…018) + owner's explicit approval before submit |

## 4. Rollback strategy

| Situation | Action |
|---|---|
| New build misbehaves, **no schema change** | `git checkout v<previous>` and Run from Xcode over the app; data stays |
| New build changed the schema | Older builds refuse to open a newer database (schema version check, no silent downgrade). Restore path: install the previous build → in UZee restore the backup made before updating (or the automatic pre-migration safety copy, exported from Settings → Data) |
| Bad commit on `development` | `git revert <sha>` (never force-push shared branches); CI must be green again |
| Bad milestone merge on `main` | Revert the merge commit; previous tag `v0.N.0` stays the known-good point |
| TestFlight build bad | Expire the build in App Store Connect → TestFlight; upload a fixed build with a higher build number |
| App Store release bad | Pause phased release; submit a fix (request expedited review if Critical). Already-installed copies cannot be pulled back, so data migrations must be forward-compatible and tested (DATA-024) |

Every fix follows the bug policy (BUG_REGISTRY): root cause, REG test, gate, new PATCH build.

## 5. Secrets: never committed

| Never in git | Where it lives instead |
|---|---|
| Apple ID password, app-specific passwords | Owner's head / Keychain |
| Certificates (`.p12`, `.cer` private keys), provisioning profiles | Mac Keychain, Xcode-managed |
| App Store Connect API keys (`.p8`) | Only if CI uploads are added later: GitHub Actions **encrypted secrets** |
| Backup passwords | Owner only; never stored by the app (SEC-006) |
| Real bank statements, receipts, personal data, real exports/backups | Owner's devices; tests use synthesised fixtures |

`.gitignore` covers `*.p12`, `*.p8`, `*.mobileprovision`, `*.cer`, `*.uzeebackup`, `build/`, `DerivedData/`, `xcuserdata/`, `*.xcresult`, `fixtures-private/`. CI runs a secret-pattern check (ENV-007). If a secret is ever committed: revoke/rotate it first, then remove it from history, and record it in PROJECT_STATE.
