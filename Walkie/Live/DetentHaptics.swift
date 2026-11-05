import UIKit

@MainActor
final class DetentHaptics: HapticsPlaying {
    private let generator = UIImpactFeedbackGenerator(style: .light)

    init() {
        generator.prepare()
    }

    func detent() {
        generator.impactOccurred()
        generator.prepare()
    }
}
