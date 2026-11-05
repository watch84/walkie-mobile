import SwiftUI

/// Big hold-to-talk button (`.ptt` in radio.css). Touch down presses; touch up, or the system
/// cancelling the touch, releases. `@GestureState` resets on cancellation, where `onEnded` would
/// not fire. The flash line sits underneath, as on web.
struct PushToTalkButton: View {
    let talk: TalkController

    @GestureState private var touching = false

    private let size: CGFloat = 176

    var body: some View {
        let state = talk.buttonState
        let enabled = state == .ready || state == .keying || state == .live

        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(faceFill(for: state))
                    .shadow(color: Theme.red.opacity(state == .live ? 0.55 : 0), radius: 22)
                Circle()
                    .stroke(rimColor(for: state), lineWidth: 2)

                if state == .live {
                    CountdownRing(talk: talk)
                        .padding(-8)
                }

                VStack(spacing: 6) {
                    CapsLabel(text: label(for: state), size: 13, color: labelColor(for: state))
                    if state == .live {
                        SecondsLeft(talk: talk)
                    }
                }
                .padding(.horizontal, 18)
                .multilineTextAlignment(.center)
            }
            .frame(width: size, height: size)
            .scaleEffect(touching && enabled ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: touching)
            .animation(.easeInOut(duration: 0.18), value: state)
            .contentShape(Circle())
            .gesture(holdGesture)
            .onChange(of: touching) { _, isDown in
                if isDown { talk.press() } else { talk.release() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label(for: state))
            .accessibilityHint(enabled ? Copy.Talk.hint : "")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("pushToTalkButton")

            Text(talk.flash.map(Copy.Talk.flash) ?? " ")
                .font(Theme.mono(12, weight: .medium))
                .foregroundStyle(Theme.amber)
                .multilineTextAlignment(.center)
                .frame(minHeight: 16)
                .padding(.horizontal, 24)
                .animation(.easeInOut(duration: 0.15), value: talk.flashID)
                .accessibilityIdentifier("talkFlash")
                .accessibilityAddTraits(.updatesFrequently)
        }
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($touching) { _, isDown, _ in isDown = true }
    }

    private func label(for state: TalkController.ButtonState) -> String {
        switch state {
        case .ready: Copy.Talk.ready
        case .keying: Copy.Talk.keying
        case .live: Copy.Talk.live
        case .busy: Copy.Talk.busy
        case .offAir: Copy.Talk.offAir
        case .tuning: Copy.Talk.tuning
        case .locked: Copy.Talk.locked
        case .noSignal: Copy.Talk.noSignal
        }
    }

    private func faceFill(for state: TalkController.ButtonState) -> Color {
        switch state {
        case .live: Theme.red
        case .keying: Theme.red.opacity(0.45)
        case .ready: Theme.surface
        case .busy: Theme.amberDim.opacity(0.18)
        case .locked, .tuning, .noSignal, .offAir: Theme.surface.opacity(0.6)
        }
    }

    private func rimColor(for state: TalkController.ButtonState) -> Color {
        switch state {
        case .live, .keying: Theme.red
        case .ready: Theme.amber
        case .busy: Theme.amberDim
        case .offAir: Theme.red.opacity(0.5)
        case .locked, .tuning, .noSignal: Theme.faint
        }
    }

    private func labelColor(for state: TalkController.ButtonState) -> Color {
        switch state {
        case .live, .keying: Theme.ink
        case .ready: Theme.amber
        case .busy: Theme.amberDim
        case .offAir: Theme.red
        case .locked, .tuning, .noSignal: Theme.muted
        }
    }
}

/// Drains clockwise toward the floor deadline (server `expiresAt`, else local 30 s).
private struct CountdownRing: View {
    let talk: TalkController

    var body: some View {
        TimelineView(.animation) { context in
            let fraction = talk.deadline(now: context.date).map {
                FloorCountdown.fraction(until: $0, now: context.date)
            } ?? 1
            ZStack {
                Circle().stroke(Theme.ink.opacity(0.12), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.amber, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Theme.amber.opacity(0.7), radius: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SecondsLeft: View {
    let talk: TalkController

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            let left = talk.deadline(now: context.date).map {
                FloorCountdown.wholeSecondsLeft(until: $0, now: context.date)
            } ?? 0
            Text(Copy.Talk.secondsLeft(left))
                .font(Theme.mono(12, weight: .medium))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
    }
}
