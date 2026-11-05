import SwiftUI

/// Big hold-to-talk button. Touch down presses; touch up, or the system cancelling the touch,
/// releases. `@GestureState` resets on cancellation, where `onEnded` would not fire.
struct PushToTalkButton: View {
    let talk: TalkController

    @GestureState private var touching = false

    private let size: CGFloat = 168

    var body: some View {
        let state = talk.buttonState
        let enabled = state == .ready || state == .keying || state == .live

        VStack(spacing: 14) {
            Text(talk.flash.map(Copy.Talk.flash) ?? " ")
                .font(Theme.mono(13, weight: .medium))
                .foregroundStyle(Theme.amber)
                .multilineTextAlignment(.center)
                .frame(minHeight: 18)
                .animation(.easeInOut(duration: 0.15), value: talk.flashID)
                .accessibilityIdentifier("talkFlash")

            ZStack {
                Circle()
                    .fill(fill(for: state))
                Circle()
                    .stroke(enabled ? Theme.amber.opacity(state == .ready ? 0.6 : 1) : Theme.faint, lineWidth: 1.5)

                if state == .live, let since = talk.liveSince {
                    CountdownRing(since: since, total: TalkController.floorMax)
                        .padding(-7)
                }

                VStack(spacing: 6) {
                    CapsLabel(text: label(for: state), size: 13, color: enabled ? Theme.text : Theme.dim)
                    if state == .live, let since = talk.liveSince {
                        SecondsLeft(since: since, total: TalkController.floorMax)
                    }
                }
            }
            .frame(width: size, height: size)
            .scaleEffect(touching && enabled ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: touching)
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

    private func fill(for state: TalkController.ButtonState) -> Color {
        switch state {
        case .live: Theme.amber.opacity(0.28)
        case .keying: Theme.amber.opacity(0.12)
        default: Color.white.opacity(0.04)
        }
    }
}

/// Drains clockwise over `FLOOR_MAX_MS` from the moment the transmission went live.
private struct CountdownRing: View {
    let since: Date
    let total: Duration

    var body: some View {
        TimelineView(.animation) { context in
            Circle()
                .trim(from: 0, to: remainingFraction(at: context.date))
                .stroke(Theme.amber, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.amber.opacity(0.7), radius: 6)
        }
        .accessibilityHidden(true)
    }

    private func remainingFraction(at date: Date) -> Double {
        let totalSeconds = Double(total.components.seconds) + Double(total.components.attoseconds) / 1e18
        return max(0, min(1, 1 - date.timeIntervalSince(since) / totalSeconds))
    }
}

private struct SecondsLeft: View {
    let since: Date
    let total: Duration

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(since)
            let left = max(0, Int((Double(total.components.seconds) - elapsed).rounded(.up)))
            Text(Copy.Talk.secondsLeft(left))
                .font(Theme.mono(12))
                .foregroundStyle(Theme.amber)
                .monospacedDigit()
        }
    }
}
