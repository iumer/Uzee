# UZee — Development Environment & Prerequisites

Status: **Draft v1 (2026-10-05)**. Based on discovery decisions: native iPhone + iPad app, built on your Apple M1 Mac, personal use, data on device, Apple on-device AI.

> Where commands run: every command below runs in **Terminal on your M1 Mac** (Applications → Utilities → Terminal) unless a step says "on iPhone".

---

## Summary

| Item | Bucket | Why |
|------|--------|-----|
| macOS (latest version your Mac supports) | REQUIRED NOW | Current Xcode requires a recent macOS |
| Xcode (latest from Mac App Store) | REQUIRED NOW | Only way to build iOS/iPadOS apps |
| Xcode command-line tools + license accepted | REQUIRED NOW | Building, testing, git |
| iOS Simulator runtime | REQUIRED NOW | Run the app without a phone |
| Git configured with your name/email | REQUIRED NOW | Source control |
| GitHub access from the Mac (GitHub CLI) | REQUIRED NOW | Clone and update the UZee repository |
| ~40 GB free disk space | REQUIRED NOW | Xcode + simulators + build cache |
| Apple ID signed into Xcode (free) | REQUIRED LATER (first on-phone build, Milestone 0) | Sign the app to install on your iPhone |
| iPhone with iOS 26+ and Apple Intelligence | REQUIRED LATER (first on-phone build) | App minimum OS and on-device AI |
| iPhone Developer Mode + pairing | REQUIRED LATER (first on-phone build) | Install development builds |
| Claude Code with Remote Control on the Mac | REQUIRED LATER (before implementation) | Lets Claude build and run tests on your Mac |
| Paid Apple Developer Program ($99/year) | REQUIRED LATER (TestFlight, sharing, iCloud sync; possibly Siri, see note) | Not needed to start |
| Homebrew | OPTIONAL (recommended) | Easiest way to install the GitHub CLI |
| iPad for testing | OPTIONAL | Simulator covers iPad layouts |
| SF Symbols app | OPTIONAL | Browse the system icons the design uses |

No database server, environment variables or backend are needed: data is stored inside the app on the device (exact storage technology is decided in the Architecture stage).

---

## REQUIRED NOW (Mac)

### 1. macOS
Apple menu → System Settings → General → Software Update → install the latest macOS your M1 supports.

Verify:
```bash
sw_vers
```
Expected: `ProductVersion` is the latest major version Apple offers your Mac (M1 Macs support current macOS releases).

### 2. Xcode
Install **Xcode** from the Mac App Store (large download, allow time). Open it once and let it install additional components.

Then in Terminal:
```bash
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
xcodebuild -runFirstLaunch
```

Verify:
```bash
xcodebuild -version        # Expected: Xcode 26.x or newer
xcode-select -p            # Expected: /Applications/Xcode.app/Contents/Developer
swift --version            # Expected: Swift 6.x
```

### 3. iOS Simulator runtime
Xcode → Settings → Components → make sure the latest **iOS** platform is installed (click Get if not).

Verify:
```bash
xcrun simctl list runtimes | grep iOS
```
Expected: at least one line like `iOS 26.x (...)`.

### 4. Git
Git ships with Xcode.
```bash
git --version
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git config --global init.defaultBranch main
```
Verify:
```bash
git config --global --list | grep user
```

### 5. GitHub access (via Homebrew + GitHub CLI)
Install Homebrew (follow the on-screen instructions, including the two "Next steps" lines it prints for your shell):
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```
Then:
```bash
brew install gh
gh auth login          # choose GitHub.com → HTTPS → login with a web browser
```
Verify:
```bash
brew --version
gh auth status         # Expected: Logged in to github.com account iumer
```

### 6. Disk space
```bash
df -h /
```
Expected: at least ~40 GB available.

### One-shot verification
After finishing steps 1–6, run this and paste the output into the thread:
```bash
echo "--- macOS";  sw_vers -productVersion
echo "--- Xcode";  xcodebuild -version | head -1
echo "--- Swift";  swift --version 2>&1 | head -1
echo "--- Runtimes"; xcrun simctl list runtimes | grep iOS
echo "--- Git";    git --version
echo "--- gh";     gh auth status 2>&1 | grep -i "logged in"
echo "--- Disk";   df -h / | tail -1
uname -m   # Expected: arm64
```

---

## REQUIRED LATER

### A. First on-phone build (Milestone 0)

**On the Mac:** Xcode → Settings → Accounts → **+** → Apple ID → sign in with your normal Apple ID. A "Personal Team" appears; that's enough to install on your own phone.

**On iPhone:**
1. **iOS version:** Settings → General → About → iOS Version must be **26.0 or newer** (UZee's minimum, because Apple's on-device AI framework requires it).
2. **Apple Intelligence:** Settings → Apple Intelligence & Siri → turn on. Needs iPhone 15 Pro or newer; device and Siri language set to English.
3. **Pairing:** connect the iPhone to the Mac with a cable, unlock it, tap **Trust**. In Xcode → Window → Devices and Simulators the phone should appear. After the first pairing you can enable "Connect via network" for wireless installs.
4. **Developer Mode:** after pairing, Settings → Privacy & Security → **Developer Mode** → On → restart → confirm.
5. **Trust the developer** (first install only): Settings → General → VPN & Device Management → your Apple ID → Trust.

Verify (Mac):
```bash
xcrun devicectl list devices
```
Expected: your iPhone listed with state `available (paired)`.

**Free Apple ID limits (important):**
- Apps installed with a free account **stop opening after 7 days** and must be reinstalled from Xcode (your data stays on the phone as long as you don't delete the app).
- Maximum 3 such apps on a device at once.
- Some capabilities need the paid program. Siri/App Intents voice features and iCloud are the ones that may affect UZee; this will be verified when the voice milestone starts, and if required the paid account moves to REQUIRED at that point.

### B. Claude Code with Remote Control (before implementation)
Implementation and test runs happen on your Mac, because iOS apps can only be built with Xcode on macOS. Before Milestone 0 you'll be asked to allow a Remote Control session on the UZee folder of your Mac; the card that appears in the thread walks you through it.

### C. Simulator testing
Covered by REQUIRED NOW step 3. Recommended simulators: the newest iPhone Pro model and an 11-inch iPad.

### D. Paid Apple Developer Program ($99/year) — when sharing or syncing
Needed for: TestFlight, App Store release, iCloud sync/backup via CloudKit, builds that don't expire weekly, and possibly Siri integration. Enroll at developer.apple.com/programs when we reach that milestone.

### E. TestFlight (when sharing with others)
Requires the paid program, an App Store Connect app record, a unique bundle identifier (planned: `com.<you>.uzee`), app icon, and privacy questionnaire. Covered in the Deployment Guide later.

### F. Production / App Store (future)
Distribution certificate and provisioning (Xcode-managed), App Store metadata, screenshots, privacy nutrition labels, review. Not needed for personal use.

---

## OPTIONAL

| Tool | Install | Use |
|------|---------|-----|
| SF Symbols | developer.apple.com/sf-symbols | Browse icons used by the design |
| iPad | — | Real-device iPad testing |
| GitHub Desktop | desktop.github.com | Visual git client if you prefer it to Terminal |

---

## Open technical notes
- Exact Xcode/iOS SDK versions will be pinned in ARCHITECTURE.md once you report your installed versions.
- Third-party dependencies are added only through Swift Package Manager (built into Xcode); no CocoaPods or other package managers.
