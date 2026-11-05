import SwiftUI

/// Radio screen: frequency readout, station dial, channel status and hold-to-talk.
struct RadioShellView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tuner = model.tuner
        let session = model.session
        let station = model.station

        VStack(spacing: 0) {
            OnAirLight(isAvailable: tuner.phase == .live && session.meta != nil, isOnAir: session.floor != nil)
                .padding(.top, 24)

            Spacer(minLength: 12)

            StationReadout(station: station)

            StationDial(index: station.index)
                .padding(.top, 18)

            VStack(spacing: 8) {
                StatusLine(tuner: tuner, session: session)
                    .frame(minHeight: 24)

                Text(tuner.phase == .live ? session.listenerCount.map(Copy.Radio.listeners) ?? " " : " ")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.dim)
                    .accessibilityIdentifier("listenerCount")
            }
            .padding(.top, 14)

            Spacer(minLength: 12)

            PushToTalkButton(talk: model.talk)
                .padding(.bottom, 20)

            if let name = model.profile.displayName {
                Button(Copy.Radio.you(name)) { model.editName() }
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.dim)
                    .padding(.bottom, 28)
                    .accessibilityIdentifier("editNameButton")
            }
        }
    }
}

private struct StationReadout: View {
    let station: Station

    var body: some View {
        VStack(spacing: 6) {
            Text(station.frequency)
                .font(Theme.mono(44))
                .foregroundStyle(station.isLocked ? Theme.dim : Theme.text)
                .monospacedDigit()
                .contentTransition(.numericText())
            HStack(spacing: 6) {
                if station.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                }
                CapsLabel(text: station.name, size: 12, color: station.isLocked ? Theme.dim : Theme.text)
            }
        }
        .animation(.easeOut(duration: 0.12), value: station)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.Radio.dialValue(station))
        .accessibilityIdentifier("stationReadout")
    }
}

private struct OnAirLight: View {
    let isAvailable: Bool
    let isOnAir: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isOnAir ? Color.red : Theme.faint)
                .frame(width: 8, height: 8)
                .shadow(color: .red.opacity(isOnAir ? 0.9 : 0), radius: 6)
            CapsLabel(text: Copy.Radio.onAir, size: 11, color: isOnAir ? Theme.text : Theme.faint)
        }
        .opacity(isAvailable ? 1 : 0)
        .animation(.easeInOut(duration: 0.2), value: isOnAir)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOnAir ? Copy.Radio.onAir : Copy.Radio.quiet)
        .accessibilityHidden(!isAvailable)
    }
}

private struct StatusLine: View {
    let tuner: Tuner
    let session: ChannelSession

    var body: some View {
        HStack(spacing: 10) {
            switch tuner.phase {
            case .idle, .tuning:
                status(Copy.Radio.tuningIn)
            case .locked:
                status(Copy.Radio.comingSoon)
            case .error:
                status(Copy.Radio.noSignal)
            case .offAir:
                status(Copy.Radio.offAir)
            case .live:
                if session.isReconnecting {
                    status(Copy.Radio.tuningIn)
                } else if let floor = session.floor {
                    PulseDot(pulsing: session.isFloorHolderSpeaking)
                    Text(floor.name)
                        .font(Theme.mono(16, weight: .medium))
                        .foregroundStyle(Theme.amber)
                } else {
                    status(Copy.Radio.live)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("sessionStatus")
    }

    private func status(_ text: String) -> some View {
        Text(text)
            .font(Theme.mono(14))
            .foregroundStyle(Theme.dim)
    }
}

/// Amber dot that pulses while the floor holder's audio is active.
private struct PulseDot: View {
    let pulsing: Bool

    var body: some View {
        TimelineView(.animation(paused: !pulsing)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let k = pulsing ? (sin(t * 2 * .pi * 1.6) + 1) / 2 : 0
            Circle()
                .fill(Theme.amber)
                .frame(width: 10, height: 10)
                .scaleEffect(1 + 0.3 * k)
                .shadow(color: Theme.amber.opacity(0.4 + 0.5 * k), radius: 3 + 9 * k)
        }
        .accessibilityHidden(true)
    }
}
