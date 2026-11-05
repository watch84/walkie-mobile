# walkie-mobile

The native iOS client for [Walkie](https://github.com/watch84/walkie). It's written in SwiftUI and talks to the same backend as the web app.

**Status: Milestone 1.** The app has the project scaffold, debug URL settings, display-name onboarding, the "Tap to tune in" screen, and a placeholder radio screen. It makes **no network calls** yet: no LiveKit, no API client, no dial, no push-to-talk.

## Requirements

- macOS with **Xcode 16+** (Swift 6, iOS 17 SDK or newer)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- An Apple ID, which is only needed to run on a physical iPhone. A free account works.

## Generate and open the project

The `.xcodeproj` is generated from `project.yml` and isn't committed.

```bash
brew install xcodegen
make project          # = scripts/generate.sh : xcodegen generate && open Walkie.xcodeproj
```

Other targets:

```bash
make generate         # regenerate without opening Xcode
make build            # Simulator build, no signing (iPhone 16 simulator)
make test             # unit tests on the Simulator
make build SIM_DEST='platform=iOS Simulator,name=iPhone 15'   # pick another simulator
```

Run `make generate` again after you pull changes that add or remove files, or that change `project.yml`.

In Xcode, select the **Walkie** scheme and a simulator or device, then press Run.

## Server URLs

In Debug builds, the gear icon in the top-right opens **Debug settings**. The values are saved in `UserDefaults`.

| Setting | Default | Simulator | Physical device |
| --- | --- | --- | --- |
| API base URL | `http://127.0.0.1:8787` | `http://127.0.0.1:8787` | `http://<mac-lan-ip>:8787` |
| LiveKit URL (fallback) | `ws://127.0.0.1:7880` | `ws://127.0.0.1:7880` | `ws://<mac-lan-ip>:7880` |

The Simulator shares the Mac's network, so `127.0.0.1` reaches the Mac. A physical iPhone has to use the Mac's LAN IP, and both devices need to be on the same Wi-Fi. To find the IP:

```bash
ipconfig getifaddr en0
```

The LiveKit URL is only a fallback. Later milestones will prefer the URL that the API returns. Nothing in M1 connects to either URL.

When the app first connects to a LAN address on a device, iOS asks for **Local Network** permission. Allow it. If you denied it, you can change it later in Settings > Privacy & Security > Local Network > Walkie.

## Backend (from the web walkie repo)

The backend lives in the web repo, [watch84/walkie](https://github.com/watch84/walkie):

```bash
# in a checkout of watch84/walkie
npm install
npm run dev:all
```

This serves the API on `:8787` and LiveKit on `:7880`. Once a later milestone makes the app connect from a physical device, start the backend so it advertises a LiveKit URL the phone can reach:

```bash
LIVEKIT_PUBLIC_URL=ws://<mac-lan-ip>:7880 npm run dev:all
```

## Signing with a free Apple ID

The Simulator doesn't need signing. To run on an iPhone:

1. Xcode > Settings > Accounts: add your Apple ID. This creates a **Personal Team**.
2. Copy `Configs/Local.xcconfig.example` to `Configs/Local.xcconfig` (the copy is git-ignored) and set `DEVELOPMENT_TEAM` to your Team ID. Then run `make generate`.
   - Or pick the team under Walkie target > Signing & Capabilities. That setting is lost the next time you regenerate, which is why the xcconfig is the better option.
3. Bundle ID: `com.watch84.walkie`. If Xcode says it can't register that ID, set `PRODUCT_BUNDLE_IDENTIFIER_BASE = com.<yourname>.walkie` in `Local.xcconfig`, because bundle IDs are unique per Apple account.
4. On the iPhone, turn on **Developer Mode** (Settings > Privacy & Security). After the first install, trust the developer under Settings > General > VPN & Device Management.

Limits of free provisioning: apps expire after **7 days** and have to be re-run from Xcode, you can have at most 3 sideloaded apps per device, and there's no TestFlight or App Store. M1 doesn't use any capability that needs a paid account. The `audio` background mode is a plain Info.plist key.

## Info.plist highlights

- `NSMicrophoneUsageDescription` is included now so that push-to-talk can request the mic later.
- `NSLocalNetworkUsageDescription` is required for LAN dev servers on a device.
- `NSAppTransportSecurity > NSAllowsLocalNetworking`: allows plain `http://` and `ws://` to localhost, `*.local`, and LAN IPs, for development. Public hosts still need TLS.
- `UIBackgroundModes = [audio]` keeps the radio playing when the app is in the background.

## Layout

```
project.yml                 XcodeGen spec (source of truth for the Xcode project)
Configs/                    xcconfigs; Local.xcconfig (ignored) for signing
scripts/generate.sh         xcodegen generate [+ open]
Walkie/App/                 App entry, root phase switch
Walkie/Models/              @Observable models: AppModel, ProfileStore, DebugSettings; DisplayName rules
Walkie/Features/            Onboarding (name + tune in), Radio (placeholder), Debug settings
Walkie/Support/             Copy (all user-facing strings), Theme
WalkieTests/                Swift Testing unit tests
```

`Walkie/Support/Copy.swift` and `Walkie/Models/DisplayName.swift` should match the web app's `src/radio/RadioApp.tsx` and `shared/protocol.ts`. When the two disagree, the web app is correct.
