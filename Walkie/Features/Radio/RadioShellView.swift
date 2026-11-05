import SwiftUI

/// Radio screen: channel status plus hold-to-talk. The dial (M4) replaces the channel buttons.
struct RadioShellView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let session = model.session

        VStack(spacing: 0) {
            ChannelPicker(selected: model.selectedChannel) { model.select($0) }
                .padding(.top, 20)

            Spacer()

            VStack(spacing: 18) {
                OnAirLight(isAvailable: session.meta != nil, isOnAir: session.floor != nil)

                Text(model.selectedChannel.name)
                    .font(Theme.mono(34))
                    .foregroundStyle(Theme.text)

                TickRow()
                    .frame(height: 34)
                    .padding(.horizontal, 28)

                StatusLine(session: session)
                    .frame(minHeight: 24)

                Text(session.phase == .live ? session.listenerCount.map(Copy.Radio.listeners) ?? " " : " ")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.dim)
                    .accessibilityIdentifier("listenerCount")
            }

            Spacer()

            PushToTalkButton(talk: model.talk)
                .padding(.bottom, 24)

            if let name = model.profile.displayName {
                Button(Copy.Radio.you(name)) { model.editName() }
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.dim)
                    .padding(.bottom, 32)
                    .accessibilityIdentifier("editNameButton")
            }
        }
    }
}

private struct ChannelPicker: View {
    let selected: ChannelInfo
    let onSelect: (ChannelInfo) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(ChannelInfo.live) { channel in
                let isSelected = channel == selected
                Button {
                    onSelect(channel)
                } label: {
                    Text("\(channel.number)")
                        .font(Theme.mono(15, weight: .medium))
                        .foregroundStyle(isSelected ? Theme.amber : Theme.dim)
                        .frame(width: 44, height: 44)
                        .overlay(Circle().stroke(isSelected ? Theme.amber : Theme.faint, lineWidth: 1))
                }
                .accessibilityLabel(channel.name)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("channelButton-\(channel.number)")
            }
        }
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
    let session: ChannelSession

    var body: some View {
        HStack(spacing: 10) {
            switch session.phase {
            case .idle, .tuningIn, .reconnecting:
                status(Copy.Radio.tuningIn)
            case .noSignal:
                status(Copy.Radio.noSignal)
            case .offAir:
                status(Copy.Radio.offAir)
            case .live:
                if let floor = session.floor {
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

/// Static, inert stand-in for the dial's tick marks.
private struct TickRow: View {
    var body: some View {
        GeometryReader { geo in
            let count = 17
            let spacing = geo.size.width / CGFloat(count - 1)
            ZStack(alignment: .leading) {
                ForEach(0..<count, id: \.self) { i in
                    let distance = abs(CGFloat(i) - CGFloat(count - 1) / 2) / (CGFloat(count - 1) / 2)
                    Capsule()
                        .fill(Theme.text.opacity(0.65 - 0.4 * distance))
                        .frame(width: 2, height: geo.size.height * (1 - 0.35 * distance))
                        .position(x: CGFloat(i) * spacing, y: geo.size.height / 2)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
