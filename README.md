# walkie-mobile

The native iOS client for [Walkie](https://github.com/watch84/walkie). It's written in SwiftUI and talks to the same backend as the web app.

**Status: Milestone 5 (polish; all milestones done).**
- **Dial:** a horizontal station dial covers the 12 stations from the web app: 3 live channels (92.9, 94.5, 96.1) and 9 locked "Coming soon" stations. When the dial rests on a live station for 300 ms, the app joins that channel's LiveKit room. Locked stations never touch the network.
- **Talking:** holding the big button takes the floor and publishes your microphone. The countdown ring follows the server's `expiresAt`.
- **Speakers:** you can mute a speaker for yourself (long-press the speaker pill, or tap the Mute chip), or report them.
- **Interruptions:** phone calls, Siri, and backgrounding end your transmission and give the floor back. Listening resumes after an interruption.
- **Sound and look:** static, room tone, detent clicks, and haptics are generated in code. The look follows the web app's `radio.css` colours.

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

**Run `make project` (or `make generate`) after every `git pull`.** `Walkie.xcodeproj` is generated and git-ignored, so pulling new Swift files doesn't add them to it. A stale project shows errors like "Cannot find type 'ChannelSession' in scope". The app target has a **Check Xcode project is current** build step. It fails with a message naming any Swift file that's missing from the project, or when `project.yml` is newer than the project.

In Xcode, select the **Walkie** scheme and a simulator or device, then press Run.

### Troubleshooting a stale project

```bash
git pull
make project          # regenerates Walkie.xcodeproj and reopens it
```

Then in Xcode:

1. If Xcode asks, choose **Revert** or **Keep Xcode Version** so it reloads the project from disk.
2. **File > Packages > Resolve Package Versions**. This is only needed if LiveKit shows as missing.
3. **Product > Clean Build Folder** (Shift-Cmd-K), then build.

## Server URLs

In Debug builds, the gear icon in the bottom-left corner opens **Debug settings**. The values are saved in `UserDefaults`.

Debug and Release builds default to the live servers, so a fresh install joins over Wi-Fi or cellular without any setup. To use a local backend, override the URLs as shown in the last two columns.

| Setting | Default (live) | Local backend, Simulator | Local backend, physical device |
| --- | --- | --- | --- |
| API base URL | `https://walkie-radial.fly.dev` | `http://127.0.0.1:8787` | `http://<mac-lan-ip>:8787` |
| LiveKit URL (fallback) | `wss://walkie-pfv6bw45.livekit.cloud` | `ws://127.0.0.1:7880` | `ws://<mac-lan-ip>:7880` |

For a local backend, the Simulator shares the Mac's network, so `127.0.0.1` reaches the Mac. A physical iPhone has to use the Mac's LAN IP, and both devices need to be on the same Wi-Fi. To find the IP:

```bash
ipconfig getifaddr en0
```

`POST /token` returns the LiveKit URL to use. If it returns a relative URL, such as the web app's `/livekit` dev proxy, there's no page origin to resolve it against, so the app uses the fallback LiveKit URL instead. An absolute `http(s)` URL is used as `ws(s)`. Edits in Debug settings take effect on the next join attempt; switching channel forces one.

The build-time defaults come from `WALKIE_API_BASE_URL` and `WALKIE_LIVEKIT_URL` in `Configs/Base.xcconfig`. To point a build at your Mac without typing URLs on the phone, override them in `Configs/Local.xcconfig` (see the example file). Values already saved in Debug settings take precedence over these defaults; **Reset to defaults** goes back to the build's values.

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

1. Start the backend with `LIVEKIT_PUBLIC_URL=ws://127.0.0.1:7880 npm run dev:all`, and point the app at it with the Simulator URLs from Server URLs (in `Configs/Local.xcconfig` or Debug settings).
2. Open the web app (the URL `npm run dev:all` prints) in **two browser windows**. Give each a different name, and tune both to **Channel 1**.
3. Run the iOS app in the Simulator. Enter a name and tap **Continue**. Returning users tap **Tap to tune in** instead. The status pill shows **Tuning in…** and then **Quiet on the channel**. The listener count goes up by one, and both web windows should see the extra listener.
4. In web window A, hold push-to-talk and speak. On iOS:
   - The **On Air** light turns on and A's name appears with an amber dot.
   - The dot pulses while A's audio is active.
   - You hear A through the Mac speakers.

   Web window B should behave the same way. That's your control.
5. Release push-to-talk. On iOS, the On air pill goes dark and the status returns to **Quiet on the channel**. This also happens when the 30-second floor limit is reached.
6. Turn the dial to 94.5 or 96.1. The app leaves the current room and joins the new one once the dial rests.
7. Stop the backend. The room drops, and the app shows **Tuning in…** and retries every 2 seconds. While `/token` can't be reached, it shows **No signal. Retrying…** and keeps retrying every 2 seconds, then rejoins when the backend is back. If the channel goes off air, either as a 403 `off_air` from `/token` or as `offAir: true` in the room metadata while connected, the app leaves the room, shows **Channel off air**, and retries every 10 seconds.

On a physical iPhone, use the LAN IP for `LIVEKIT_PUBLIC_URL` and the two Debug settings URLs, and allow Local Network access when iOS asks.

Logs: in Console.app, filter on subsystem `com.watch84.walkie` (categories `session` and `audio`).

## Verify: dial, tuning rules, sounds (M4)

Start the backend and run the app as in the sections above. Turn the Mac volume up so you can hear the beds.

1. **Tune in.** The dial starts on **92.9 Channel 1**, or the station you last rested on, which is saved as `walkie:station`. The status pill reads **Tuning in…** over static, then **Quiet on the channel**. Once the channel is quiet, the static gives way to soft room tone.
2. **Drag slowly left onto 97.7 Lo-Fi Desk.**
   - Each station you pass gives a click, and a light haptic on a device.
   - The readout shows a lock and the station name, and the status line reads **Coming soon**.
   - The talk button reads **Coming soon** and does nothing.
   - You hear static.
   - The Channel 1 room is left immediately. Web windows see the listener count drop.
   - The backend log should show **no** `/token` request for the locked station.
3. **Flick hard from 88.1 toward 105.7.** The dial coasts, rubber-bands past the end, and bounces back onto 105.7. Dragging past either end resists and springs back.
4. **Fast scroll across the live stations** (for example, flick from 88.1 so it passes 92.9–96.1 and stops on 96.1). The backend should log exactly **one** `/token` request, for `channel-3`, about 300 ms after the dial stops. Passing over 92.9 and 94.5 doesn't connect.
5. **Rest on 94.5 Channel 2.** You hear static and **Tuning in…**, then **Quiet on the channel** and room tone. A web window on Channel 2 sees you join.
6. **Talk from the web window on that channel.** The room tone stops while the floor is held and you hear the speaker. It comes back after they release. Holding the iOS button also silences the bed while you talk.
7. **Off air:** take the channel off air. The status line reads **Channel off air** with silence, and the app retries every 10 seconds. If a connected room drops for another reason, the app shows **Tuning in…** with static and retries after 2 seconds.
8. **VoiceOver:** the dial is an adjustable element. Swipe up or down to move one station. The value is read as "92.9, Channel 1", or "88.1, Morning Static, Coming soon".
9. **Reduce Motion** (Settings > Accessibility > Motion): a flick settles on the nearest station without coasting.

## Verify: polish and edge cases (M5)

1. **Look:**
   - Black background; the header reads `walkie`, then the listener count, then the **On air** pill. The pill lights red (`#ff4b33`) while anyone holds the floor.
   - The frequency is large, with tabular digits. The station name is amber and uppercase. Locked stations are dimmed and show a lock.
   - The talk button is a round face with an amber rim when ready, red while keying up and live, an amber-dim tint when the channel is busy, and muted when disabled.
   - Flash messages appear under the button.
2. **Countdown:** hold to talk. The ring and seconds count down from the server's `floor.expiresAt`, starting at 30 seconds and reaching zero when the server revokes the floor ("Transmission ended"). Until the first metadata update arrives, it counts from your key-up time.
3. **Mute (local only):** while a web window talks, either long-press the speaker pill (about half a second) or tap **Mute**.
   - The flash reads "Muted {name} for you". The audio stops on iOS only; other web windows still hear them. The pill shows a crossed-out speaker.
   - Long-press again, or tap **Unmute**, and you see "Unmuted {name}".
   - The mute stays on if they key up again, and applies again when you return to that channel.
   - No API request is made.
4. **Report:** while someone else holds the floor, or for 2 minutes after they release, tap **Report**.
   - The backend receives `POST /report` with `{channel, identity, name, key, reportedIdentity, reportedName}`.
   - Success flashes "Reported {name}. Thanks." and the chip changes to **Reported**, disabled. Failure flashes "Report failed. Try again."
   - The chips never appear for your own transmissions.
5. **Status pills:** check each one:
   - **Coming soon**, on locked stations.
   - **Tuning in…**
   - **Reconnecting…**, on a brief network loss: toggle the Mac's Wi-Fi for a second.
   - **No signal. Retrying…**, when the API is down.
   - **Channel off air**, red, retrying every 10 seconds.
   - **Quiet on the channel**.
   - **You’re on air**, while you talk.
   - The speaker's name with a pulsing dot. The dot doesn't pulse under Reduce Motion.
6. **Backgrounding:** while holding, swipe home. The app keeps itself alive briefly (a background task) until `/floor/release` and the unpublish have gone out. The web window's On air light should go off within a second.
7. **Interruptions:** on a device, while talking, trigger Siri or take a call (FaceTime audio works). The transmission ends with "Transmission ended" and the floor is released. When the interruption ends, the app reactivates `.playAndRecord` with the speaker as the default output, restarts the sound beds, and keeps listening. In the Simulator, **Device > Trigger Siri** (if your Xcode has it) or an alarm exercises the same path.
8. **Speaker routing:** with no headphones connected, audio comes from the loudspeaker, not the earpiece. Plug in or unplug headphones, or connect Bluetooth, and audio follows the route. If anything changes the audio category, the app switches back to `.playAndRecord`.

## Verify: iOS push-to-talk, heard on the web

1. Start the backend and tune the iOS app and a web window to the same channel, as in the section above.
2. **The first press only asks for the microphone.** Tap the button once and allow access. It doesn't key up behind the system dialog. If you deny access, the button shows "Microphone blocked. Allow it in Settings." To fix it, go to Settings > Privacy & Security > Microphone > Walkie, or reset the Simulator.
3. **Hold the button and speak.** While it's keying up, the label reads **Keying up…**: the app has sent `POST /floor/request` and is waiting up to 4 seconds for the server to grant `canPublish`. Then:
   - The app plays a short rising chirp.
   - The button reads **On air**, with an amber countdown ring and seconds left, starting at 30.
   - The web window shows you as the speaker with its On Air light on, and you hear yourself there.
   - **The Simulator uses the Mac's microphone**, so use headphones on the Mac or mute the web window's speakers to avoid feedback.
4. **Let go.** The app plays a falling chirp, sends `POST /floor/release`, and unpublishes the mic. The web window goes quiet.
5. **Busy:** while the web window holds the floor, the iOS button reads **Channel busy** and is disabled. Pressing it only flashes "Channel busy". If the server answers a floor request with 409, you see the same flash.
6. **30-second cap:** keep holding past 30 seconds. The server revokes publish, and the app stops transmitting and flashes **Transmission ended**.
7. **Backgrounding:** while holding, swipe home (Shift-Cmd-H in the Simulator). The transmission ends and the floor is released.
8. **Off air:** taking the channel off air shows **Channel off air**. Other floor failures flash **Couldn't key up. Try again.**

On a physical iPhone, the phone's own microphone is used. Allow Local Network and Microphone access when iOS asks.

## Signing with a free Apple ID

The Simulator doesn't need signing. To run on an iPhone:

1. Xcode > Settings > Accounts: add your Apple ID. This creates a **Personal Team**.
2. Copy `Configs/Local.xcconfig.example` to `Configs/Local.xcconfig` (the copy is git-ignored) and set `DEVELOPMENT_TEAM` to your Team ID. Then run `make generate`.
   - Or pick the team under Walkie target > Signing & Capabilities. That setting is lost the next time you regenerate, which is why the xcconfig is the better option.
3. Bundle ID: `com.watch84.walkie`. If Xcode says it can't register that ID, set `PRODUCT_BUNDLE_IDENTIFIER_BASE = com.<yourname>.walkie` in `Local.xcconfig`, because bundle IDs are unique per Apple account.
4. On the iPhone, turn on **Developer Mode** (Settings > Privacy & Security). After the first install, trust the developer under Settings > General > VPN & Device Management.

Limits of free provisioning: apps expire after **7 days** and have to be re-run from Xcode, you can have at most 3 sideloaded apps per device, and there's no TestFlight or App Store. The app doesn't use any capability that needs a paid account. The `audio` background mode is a plain Info.plist key.

## Info.plist highlights

- `NSMicrophoneUsageDescription`: shown the first time you press the talk button.
- `WalkieAPIBaseURL` and `WalkieLiveKitURL` come from the xcconfig variables described in Server URLs.
- `NSLocalNetworkUsageDescription` is required for LAN dev servers on a device.
- `NSAppTransportSecurity > NSAllowsLocalNetworking`: the default servers use HTTPS/WSS; this allows plain `http://` and `ws://` to localhost, `*.local`, and LAN IPs, for a local backend. Public hosts still need TLS.
- `UIBackgroundModes = [audio]` keeps the radio playing when the app is in the background.

The audio session is set to `.playAndRecord` with `.defaultToSpeaker` and `.allowBluetooth` on the first tune-in. LiveKit's automatic audio-session management is turned off so that it doesn't switch to `.playback`.

## Layout

```
project.yml                 XcodeGen spec (source of truth for the Xcode project)
Configs/                    xcconfigs; Local.xcconfig (ignored) for signing
scripts/generate.sh         xcodegen generate [+ open]
Walkie/App/                 App entry, root phase switch
Walkie/Models/              @Observable models: AppModel (+ AppDependencies), ProfileStore, DebugSettings; DisplayName rules; Stations (stations.ts)
Walkie/Networking/          protocol.ts mirror (Codable), HTTPWalkieAPI, LiveKit URL resolution
Walkie/Session/             Tuner (tuner.ts), ChannelSession (one room, metadata, mute set), TalkController (push-to-talk), ReportController (report + mute), FlashLine + FloorCountdown, RoomTransport
Walkie/Live/                Apple-only: LiveKitTransport, AVAudioSession, mic permission, chirps, RadioSoundEngine (beds + click), haptics
Walkie/Features/            Onboarding (name + tune in), Radio (StationDial, readout, status, hold-to-talk), Debug settings
Walkie/Support/             Copy (all user-facing strings), Theme, DialMotion (motion.ts), SoundBed rules, ToneSynth
WalkieTests/                Swift Testing unit tests
```

These files mirror the web app, and the web app is correct when they disagree:

- `Walkie/Support/Copy.swift` and `Walkie/Models/DisplayName.swift` mirror `src/radio/RadioApp.tsx`.
- `Walkie/Networking/Protocol.swift` mirrors `shared/protocol.ts`.

Everything except `Walkie/Live/` and the SwiftUI views is plain Foundation code, so the unit tests run against fakes and never touch LiveKit.
