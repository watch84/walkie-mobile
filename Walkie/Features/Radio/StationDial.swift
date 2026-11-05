import SwiftUI
import UIKit

/// Drives `DialMotion` from touches and a display link, and reports detent crossings.
@MainActor
@Observable
final class DialController {
    private(set) var motion: DialMotion

    var position: Double { motion.position }

    /// A detent was crossed while dragging, coasting or settling (haptic + click).
    @ObservationIgnored var onDetent: () -> Void = {}
    /// The station under the pointer changed.
    @ObservationIgnored var onIndexChange: (Int) -> Void = { _ in }

    @ObservationIgnored private var lastIndex: Int
    @ObservationIgnored private var dragOrigin: Double = 0
    @ObservationIgnored private var isDragging = false
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var lastTimestamp: CFTimeInterval?
    @ObservationIgnored private let proxy = DisplayLinkProxy()

    init(count: Int, index: Int) {
        let initial = DialMotion(count: count, index: index)
        motion = initial
        lastIndex = initial.currentIndex
        proxy.handler = { [weak self] link in self?.tick(link) }
    }

    func dragChanged(translation: CGFloat, spacing: CGFloat) {
        if !isDragging {
            isDragging = true
            stopDisplayLink()
            dragOrigin = motion.beginDrag()
        }
        motion.drag(to: dragOrigin - Double(translation / spacing))
        reportIndex()
    }

    func dragEnded(velocity: CGFloat, spacing: CGFloat, reduceMotion: Bool) {
        isDragging = false
        motion.endDrag(velocity: -Double(velocity / spacing), reduceMotion: reduceMotion)
        startDisplayLink()
    }

    /// Accessibility increment/decrement, or any programmatic move.
    func move(by delta: Int, reduceMotion: Bool) {
        let target = DialMotion.clamp(motion.restingIndex + delta, count: motion.count)
        if reduceMotion {
            motion.snap(to: target)
            reportIndex()
        } else {
            motion.glide(to: target)
            startDisplayLink()
        }
    }

    private func reportIndex() {
        let index = motion.currentIndex
        guard index != lastIndex else { return }
        lastIndex = index
        onDetent()
        onIndexChange(index)
    }

    private func tick(_ link: CADisplayLink) {
        let dt = lastTimestamp.map { min(link.timestamp - $0, 1.0 / 30) } ?? (1.0 / 60)
        lastTimestamp = link.timestamp
        let moving = motion.step(dt)
        reportIndex()
        if !moving { stopDisplayLink() }
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        lastTimestamp = nil
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }
}

/// `CADisplayLink` retains its target; the proxy keeps the controller out of that cycle.
@MainActor
private final class DisplayLinkProxy: NSObject {
    var handler: (CADisplayLink) -> Void = { _ in }

    @objc func tick(_ link: CADisplayLink) {
        handler(link)
    }
}

/// Horizontal snap dial across `Stations.all`: tick strip, frequency labels and a fixed
/// center pointer. Drag or flick; it rubber-bands at the ends and settles on a station.
struct StationDial: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var controller: DialController

    private let spacing: CGFloat = 72
    private let minorTicks = 4

    init(index: Int) {
        _controller = State(initialValue: DialController(count: Stations.all.count, index: index))
    }

    var body: some View {
        GeometryReader { geo in
            let center = geo.size.width / 2
            let position = controller.position

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    drawTicks(in: &context, size: size, position: position)
                }

                ForEach(Stations.all) { station in
                    let x = center + (CGFloat(station.index) - CGFloat(position)) * spacing
                    if x > -spacing, x < geo.size.width + spacing {
                        StationLabel(station: station, distance: abs(Double(station.index) - position))
                            .position(x: x, y: geo.size.height - 12)
                    }
                }

                Capsule()
                    .fill(Theme.amber)
                    .frame(width: 2, height: geo.size.height - 30)
                    .shadow(color: Theme.amber.opacity(0.8), radius: 4)
                    .position(x: center, y: (geo.size.height - 30) / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        controller.dragChanged(translation: value.translation.width, spacing: spacing)
                    }
                    .onEnded { value in
                        controller.dragEnded(velocity: value.velocity.width, spacing: spacing, reduceMotion: reduceMotion)
                    }
            )
        }
        .frame(height: 86)
        .mask(
            LinearGradient(
                stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.18),
                        .init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
                startPoint: .leading, endPoint: .trailing
            )
        )
        .onAppear {
            controller.onDetent = { model.detentCrossed() }
            controller.onIndexChange = { model.selectStation($0) }
        }
        .accessibilityElement()
        .accessibilityLabel(Copy.Radio.dialLabel)
        .accessibilityValue(Copy.Radio.dialValue(model.station))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: controller.move(by: 1, reduceMotion: reduceMotion)
            case .decrement: controller.move(by: -1, reduceMotion: reduceMotion)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("stationDial")
    }

    private func drawTicks(in context: inout GraphicsContext, size: CGSize, position: Double) {
        let center = size.width / 2
        let step = spacing / CGFloat(minorTicks + 1)
        let tickArea = size.height - 30
        let total = (Stations.all.count - 1) * (minorTicks + 1)
        for tick in 0...total {
            let x = center + (CGFloat(tick) * step - CGFloat(position) * spacing)
            guard x > -step, x < size.width + step else { continue }
            let isMajor = tick % (minorTicks + 1) == 0
            let height = isMajor ? tickArea * 0.8 : tickArea * 0.42
            let distance = abs(x - center) / (size.width / 2)
            let opacity = (isMajor ? 0.85 : 0.4) * (1 - 0.55 * min(1, distance))
            let rect = CGRect(x: x - 1, y: (tickArea - height) / 2, width: 2, height: height)
            context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(Theme.text.opacity(opacity)))
        }
    }
}

private struct StationLabel: View {
    let station: Station
    let distance: Double

    var body: some View {
        HStack(spacing: 3) {
            if station.isLocked {
                Image(systemName: "lock.fill")
                    .font(.system(size: 8))
            }
            Text(station.frequency)
                .font(Theme.mono(11))
        }
        .foregroundStyle(station.isLocked ? Theme.dim : Theme.text)
        .opacity(max(0.25, 1 - distance * 0.25))
        .fixedSize()
        .accessibilityHidden(true)
    }
}
