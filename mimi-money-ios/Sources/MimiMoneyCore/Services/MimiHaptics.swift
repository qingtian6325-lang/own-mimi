import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Instant tactile feedback helper for iOS (silent no-op on macOS unit tests).
@MainActor
public enum MimiHaptics {
    public static func light() {
        #if os(iOS)
        guard MimiStore.shared.hapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    public static func medium() {
        #if os(iOS)
        guard MimiStore.shared.hapticsEnabled else { return }
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }

    public static func selection() {
        #if os(iOS)
        guard MimiStore.shared.hapticsEnabled else { return }
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
        #endif
    }
}
