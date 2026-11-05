import SwiftUI

/// Radio screen, laid out like the web client's RadioApp: header (brand · listeners · On air),
/// frequency readout, station dial, status pill with speaker chips, hold-to-talk, flash line.
struct RadioShellView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let tuner = model.tuner
        let session = model.session
        let station = model.station

        VStack(spacing: 0) {
            Header(
                listeners: tuner.phase == .live ? session.listenerCount : nil,
                isOnAir: tuner.phase == .live && session.floor != nil
            )
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Spacer(minLength: 8)

            StationReadout(station: station)

            StationDial(index: station.index)
                .padding(.top, 16)

            VStack(spacing: 12) {
                StatusPill(model: model)
                SpeakerChips(model: model)
            }
            .frame(minHeight: 84, alignment: .top)
            .padding(.top, 14)

            Spacer(minLength: 8)

            PushToTalkButton(talk: model.talk)

            if let name = model.profile.displayName {
                Button(Copy.Radio.you(name)) { model.editName() }
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 10)
                    .padding(.bottom, 16)
                    .accessibilityIdentifier("editNameButton")
            }
        }
    }
}

private struct Header: View {
    let listeners: Int?
    let isOnAir: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(Copy.brand)
                .font(Theme.mono(15, weight: .semibold))
                .tracking(3)
                .foregroundStyle(Theme.amber)

            Spacer()

            Text(listeners.map(Copy.Radio.listeners) ?? " ")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.muted)
                .accessibilityIdentifier("listenerCount")

            OnAirPill(isLit: isOnAir)
        }
    }
}

private struct OnAirPill: View {
    let isLit: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isLit ? Theme.ink : Theme.faint)
                .frame(width: 6, height: 6)
            Text(Copy.Radio.onAir.uppercased())
                .font(Theme.mono(10, weight: .semibold))
                .tracking(2)
        }
        .foregroundStyle(isLit ? Theme.ink : Theme.faint)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(isLit ? Theme.red : Color.clear))
        .overlay(Capsule().stroke(isLit ? Theme.red : Theme.faint, lineWidth: 1))
        .shadow(color: Theme.red.opacity(isLit ? 0.6 : 0), radius: 8)
        .animation(.easeInOut(duration: 0.2), value: isLit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isLit ? Copy.Radio.onAir : Copy.Radio.quiet)
        .accessibilityIdentifier("onAirPill")
    }
}

private struct StationReadout: View {
    let station: Station

    var body: some View {
        VStack(spacing: 8) {
            Text(station.frequency)
                .font(Theme.mono(60, weight: .light))
                .monospacedDigit()
                .foregroundStyle(station.isLocked ? Theme.faint : Theme.ink)
                .contentTransition(.numericText())
            HStack(spacing: 6) {
                if station.isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11))
                }
                CapsLabel(text: station.name, size: 12, color: station.isLocked ? Theme.muted : Theme.amber)
            }
            .foregroundStyle(Theme.muted)
        }
        .animation(.easeOut(duration: 0.12), value: station)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Copy.Radio.dialValue(station))
        .accessibilityIdentifier("stationReadout")
    }
}

/// Tuner and floor state as a pill. Long-pressing a speaker toggles local mute.
private struct StatusPill: View {
    let model: AppModel

    var body: some View {
        let tuner = model.tuner
        let session = model.session

        Group {
            switch tuner.phase {
            case .idle, .tuning:
                Pill { label(Copy.Radio.tuningIn, color: Theme.muted) }
            case .locked:
                Pill {
                    Image(systemName: "lock.fill").font(.system(size: 10)).foregroundStyle(Theme.muted)
                    label(Copy.Radio.comingSoon, color: Theme.muted)
                }
            case .error:
                Pill { label(Copy.Radio.noSignal, color: Theme.muted) }
            case .offAir:
                Pill(stroke: Theme.red, fill: Theme.red.opacity(0.12)) {
                    Circle().fill(Theme.red).frame(width: 6, height: 6)
                    label(Copy.Radio.offAir, color: Theme.red)
                }
            case .live:
                if session.isReconnecting {
                    Pill { label(Copy.Radio.reconnecting, color: Theme.muted) }
                } else if session.isFloorHeldByMe || model.talk.phase == .live {
                    Pill(stroke: Theme.red, fill: Theme.red.opacity(0.15)) {
                        PulseDot(color: Theme.red, pulsing: true)
                        label(Copy.Radio.youreOnAir, color: Theme.ink)
                    }
                } else if let floor = session.floor {
                    SpeakerPill(model: model, speaker: floor)
                } else {
                    Pill { label(Copy.Radio.quiet, color: Theme.muted) }
                }
            }
        }
        .accessibilityIdentifier("sessionStatus")
    }

    private func label(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Theme.mono(13))
            .foregroundStyle(color)
    }
}

private struct SpeakerPill: View {
    let model: AppModel
    let speaker: FloorHolder

    var body: some View {
        let muted = model.session.isMuted(speaker.identity)
        Pill(stroke: Theme.amberDim, fill: Theme.amber.opacity(0.08)) {
            PulseDot(color: Theme.amber, pulsing: model.session.isFloorHolderSpeaking && !muted)
            Text(speaker.name)
                .font(Theme.mono(14, weight: .medium))
                .foregroundStyle(muted ? Theme.muted : Theme.amber)
            if muted {
                Image(systemName: "speaker.slash.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
            }
        }
        .onLongPressGesture(minimumDuration: 0.55) {
            model.report.toggleMute(speaker)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Copy.Radio.muteHint(speaker.name))
        .accessibilityAction(named: muted ? Copy.Radio.unmute : Copy.Radio.mute) {
            model.report.toggleMute(speaker)
        }
    }
}

/// Mute and Report for the current or most recent (≤ 2 min) other speaker.
private struct SpeakerChips: View {
    let model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            if model.tuner.phase == .live, let target = model.report.target(at: context.date) {
                let muted = model.session.isMuted(target.identity)
                let reportable = model.report.canReport(target)
                HStack(spacing: 10) {
                    Chip(
                        title: muted ? Copy.Radio.unmute : Copy.Radio.mute,
                        systemImage: muted ? "speaker.wave.2" : "speaker.slash",
                        enabled: true
                    ) { model.report.toggleMute(target) }
                    .accessibilityIdentifier("muteChip")

                    Chip(
                        title: model.report.reportedIdentities.contains(target.identity) ? Copy.Radio.reported : Copy.Radio.report,
                        systemImage: "flag",
                        enabled: reportable
                    ) { Task { await model.report.report(target) } }
                    .accessibilityIdentifier("reportChip")
                }
                .transition(.opacity)
            }
        }
    }
}

private struct Chip: View {
    let title: String
    let systemImage: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 10))
                Text(title.uppercased())
                    .font(Theme.mono(10, weight: .semibold))
                    .tracking(1.5)
            }
            .foregroundStyle(enabled ? Theme.ink : Theme.faint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(Capsule().stroke(enabled ? Theme.muted : Theme.faint, lineWidth: 1))
        }
        .disabled(!enabled)
    }
}

/// Dot that pulses while audio is active; static under Reduce Motion.
private struct PulseDot: View {
    let color: Color
    let pulsing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let animate = pulsing && !reduceMotion
        TimelineView(.animation(paused: !animate)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let k = animate ? (sin(t * 2 * .pi * 1.6) + 1) / 2 : (pulsing ? 1 : 0)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .scaleEffect(1 + 0.3 * k)
                .shadow(color: color.opacity(0.4 + 0.5 * k), radius: 3 + 8 * k)
        }
        .accessibilityHidden(true)
    }
}
