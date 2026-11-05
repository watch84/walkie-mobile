# walkie-mobile

The native iOS client for [Walkie](https://github.com/watch84/walkie). It's written in SwiftUI and talks to the same backend as the web app.

**Status: Milestone 2 (listen only).** After "Tap to tune in", the app fetches a token from the web walkie API, joins the channel's LiveKit room, and plays whoever is talking. It shows the connection state, the number of listeners, the current speaker, and an On Air light, all driven by the server's room metadata. You can pick one of the three live channels with a temporary picker; the dial arrives in M4. Push-to-talk is a disabled placeholder until M3.

## Requirements

- macOS with **Xcode 16.3+** (Swift 6.1 tools, which current LiveKit Swift SDK releases require; iOS 17+ deployment target)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- An Apple ID, which is only needed to run on a physical iPhone. A free account works.

## Generate and open the project

The `.xcodeproj` is generated from `project.yml` and isn't committed. The [LiveKit Swift SDK](https://github.com/livekit/client-sdk-swift) is a Swift Package dependency (2.7.0 up to the next major version). The first time you open the project, Xcode resolves and downloads it, which takes a while.

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

`POST /token` returns the LiveKit URL to use. If it returns a relative URL, such as the web app's `/livekit` dev proxy, there's no page origin to resolve it against, so the app uses the fallback LiveKit URL instead. An absolute `http(s)` URL is used as `ws(s)`. Edits in Debug settings take effect on the next join attempt; switching channel forces one.

The build-time defaults come from `WALKIE_API_BASE_URL` and `WALKIE_LIVEKIT_URL` in `Configs/Base.xcconfig`. To point a device build at your Mac without typing URLs on the phone, override them in `Configs/Local.xcconfig` (see the example file). Values already saved in Debug settings take precedence over these defaults.

When the app first connects to a LAN address on a device, iOS asks for **Local Network** permission. Allow it. If you denied it, you can change it later in Settings > Privacy & Security > Local Network > Walkie.

## Backend (from the web walkie repo)

The backend lives in the web repo, [watch84/walkie](https://github.com/watch84/walkie):

```bash
# in a checkout of watch84/walkie
npm install
npm run dev:all
```

This serves the API on `:8787` and LiveKit on `:7880`. Set `LIVEKIT_PUBLIC_URL` so `/token` returns a URL the iOS app can reach:

```bash
# Simulator
LIVEKIT_PUBLIC_URL=ws://127.0.0.1:7880 npm run dev:all

# Physical iPhone (same Wi-Fi as the Mac)
LIVEKIT_PUBLIC_URL=ws://<mac-lan-ip>:7880 npm run dev:all
```

If you don't set it, the API may return `/livekit`, and the app falls back to the LiveKit URL in Debug settings. That works too, as long as the fallback is correct for the Simulator or device.

### Firewall

If the macOS firewall is on, allow incoming connections for `node` and `livekit-server` (macOS asks the first time), or open these ports:

| Port | Protocol | Used for |
| --- | --- | --- |
| 8787 | TCP | Walkie API (`/token`, and later `/floor/*` and `/report`) |
| 7880 | TCP | LiveKit signaling (WebSocket) |
| 7881 | TCP | LiveKit media over TCP (fallback) |
| 7882 | UDP | LiveKit media (`livekit-server --dev`) |
| 50000–60000 | UDP | LiveKit media, if your LiveKit config uses a port range instead of 7882 |

The Simulator uses loopback and usually isn't affected by the firewall. A physical device always is.

## Verify: web push-to-talk, heard on iOS

1. Start the backend with `LIVEKIT_PUBLIC_URL=ws://127.0.0.1:7880 npm run dev:all`.
2. Open the web app (the URL `npm run dev:all` prints) in **two browser windows**. Give each a different name, and tune both to **Channel 1**.
3. Run the iOS app in the Simulator. Enter a name and tap **Continue**. Returning users tap **Tap to tune in** instead. The status line shows **Tuning in…** and then **Live**. The listener count goes up by one, and both web windows should see the extra listener.
4. In web window A, hold push-to-talk and speak. On iOS:
   - The **On Air** light turns on and A's name appears with an amber dot.
   - The dot pulses while A's audio is active.
   - You hear A through the Mac speakers.

   Web window B should behave the same way. That's your control.
5. Release push-to-talk. On iOS, the light goes off and the status returns to **Live**. This also happens when the 30-second floor limit is reached.
6. Switch to channel 2 or 3 with the buttons at the top. The app leaves the current room and joins the new one.
7. Stop the backend. The app shows **No signal** and retries every 10 seconds, then rejoins when the backend is back. If the server reports the channel as off air (403 `off_air`), the app shows **Channel off air** and retries every 10 seconds.

On a physical iPhone, use the LAN IP for `LIVEKIT_PUBLIC_URL` and the two Debug settings URLs, and allow Local Network access when iOS asks.

Logs: in Console.app, filter on subsystem `com.watch84.walkie` (categories `session` and `audio`).

## Signing with a free Apple ID

The Simulator doesn't need signing. To run on an iPhone:

1. Xcode > Settings > Accounts: add your Apple ID. This creates a **Personal Team**.
2. Copy `Configs/Local.xcconfig.example` to `Configs/Local.xcconfig` (the copy is git-ignored) and set `DEVELOPMENT_TEAM` to your Team ID. Then run `make generate`.
   - Or pick the team under Walkie target > Signing & Capabilities. That setting is lost the next time you regenerate, which is why the xcconfig is the better option.
3. Bundle ID: `com.watch84.walkie`. If Xcode says it can't register that ID, set `PRODUCT_BUNDLE_IDENTIFIER_BASE = com.<yourname>.walkie` in `Local.xcconfig`, because bundle IDs are unique per Apple account.
4. On the iPhone, turn on **Developer Mode** (Settings > Privacy & Security). After the first install, trust the developer under Settings > General > VPN & Device Management.

Limits of free provisioning: apps expire after **7 days** and have to be re-run from Xcode, you can have at most 3 sideloaded apps per device, and there's no TestFlight or App Store. The app doesn't use any capability that needs a paid account. The `audio` background mode is a plain Info.plist key.

## Info.plist highlights

- `NSMicrophoneUsageDescription` is included now so that push-to-talk can request the mic later. M2 never records audio, so iOS doesn't ask for the mic yet.
- `WalkieAPIBaseURL` and `WalkieLiveKitURL` come from the xcconfig variables described in Server URLs.
- `NSLocalNetworkUsageDescription` is required for LAN dev servers on a device.
- `NSAppTransportSecurity > NSAllowsLocalNetworking`: allows plain `http://` and `ws://` to localhost, `*.local`, and LAN IPs, for development. Public hosts still need TLS.
- `UIBackgroundModes = [audio]` keeps the radio playing when the app is in the background.

The audio session is set to `.playAndRecord` with `.defaultToSpeaker` and `.allowBluetooth` on the first tune-in. LiveKit's automatic audio-session management is turned off so that it doesn't switch to `.playback`.

## Layout

```
project.yml                 XcodeGen spec (source of truth for the Xcode project)
Configs/                    xcconfigs; Local.xcconfig (ignored) for signing
scripts/generate.sh         xcodegen generate [+ open]
Walkie/App/                 App entry, root phase switch
Walkie/Models/              @Observable models: AppModel (+ AppDependencies), ProfileStore, DebugSettings; DisplayName rules
Walkie/Networking/          protocol.ts mirror (Codable), HTTPWalkieAPI, LiveKit URL resolution
Walkie/Session/             ChannelSession (join/retry/metadata state machine), RoomTransport abstraction
Walkie/Live/                Apple-only: LiveKitTransport, AVAudioSession setup, live dependencies
Walkie/Features/            Onboarding (name + tune in), Radio (listen-only), Debug settings
Walkie/Support/             Copy (all user-facing strings), Theme
WalkieTests/                Swift Testing unit tests
```

These files mirror the web app, and the web app is correct when they disagree:

- `Walkie/Support/Copy.swift` and `Walkie/Models/DisplayName.swift` mirror `src/radio/RadioApp.tsx`.
- `Walkie/Networking/Protocol.swift` mirrors `shared/protocol.ts`.

Everything except `Walkie/Live/` and the SwiftUI views is plain Foundation code, so the unit tests run against fakes and never touch LiveKit.
