import SwiftUI

/// Apple HIG helpers: 44pt hit targets + light press feedback.
public enum MimiHIG {
    public static let minTouch: CGFloat = 44
}

/// Native-feeling press: instant opacity + slight scale with immediate recovery and haptic feedback.
public struct MimiPressableButtonStyle: ButtonStyle {
    public var pressedOpacity: Double
    public var pressedScale: CGFloat
    public var enableHaptic: Bool

    public init(pressedOpacity: Double = 0.65, pressedScale: CGFloat = 0.98, enableHaptic: Bool = true) {
        self.pressedOpacity = pressedOpacity
        self.pressedScale = pressedScale
        self.enableHaptic = enableHaptic
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .animation(
                configuration.isPressed
                    ? .linear(duration: 0.04)
                    : .easeOut(duration: 0.10),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed && enableHaptic {
                    MimiHaptics.light()
                }
            }
    }
}

/// Shared mode-switch chip. AI entry uses the cat mascot; 手动 uses ⇌.
public struct BookkeepingModeSwitchButton: View {
    public enum LeadingIcon {
        case swap
        case mascot
    }

    public var title: String
    public var leading: LeadingIcon
    public var accessibilityName: String?
    public var action: () -> Void

    public init(
        title: String,
        leading: LeadingIcon = .swap,
        accessibilityName: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.leading = leading
        self.accessibilityName = accessibilityName
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                switch leading {
                case .swap:
                    Image(systemName: "arrow.left.arrow.right")
                        .mimiFont(13, weight: .bold)
                case .mascot:
                    MimiAskMascotView(size: 20)
                }
                Text(title)
                    .mimiFont(13, weight: .semibold)
            }
            .foregroundColor(MimiTheme.textPrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(minHeight: MimiHIG.minTouch)
            .background(Capsule().strokeBorder(MimiTheme.strokeSubtle, lineWidth: 1))
        }
        .mimiPressable()
        .accessibilityLabel(accessibilityName ?? "切换到\(title)")
    }
}

/// AI 回复文案：把 `**粗体**` 渲染成真正加粗，不显示星号。
public struct MimiChatMarkdownText: View {
    public var text: String
    public var size: CGFloat
    public var weight: Font.Weight
    public var color: Color

    public init(
        _ text: String,
        size: CGFloat = 15,
        weight: Font.Weight = .regular,
        color: Color = MimiTheme.textPrimary
    ) {
        self.text = text
        self.size = size
        self.weight = weight
        self.color = color
    }

    public var body: some View {
        Text(attributed)
            .foregroundColor(color)
            .tint(color)
    }

    private var attributed: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        let base = MimiTheme.font(size: size, weight: weight)
        let bold = MimiTheme.font(size: size, weight: .bold)
        if var parsed = try? AttributedString(markdown: text, options: options) {
            parsed.font = base
            for run in parsed.runs {
                if let intent = run.inlinePresentationIntent,
                   intent.contains(.stronglyEmphasized) {
                    parsed[run.range].font = bold
                }
            }
            return parsed
        }
        var plain = AttributedString(text)
        plain.font = base
        return plain
    }
}

public extension View {
    /// Expand the tappable area to at least 44×44 pt without forcing a larger visual.
    func mimiMinTouchTarget(_ size: CGFloat = MimiHIG.minTouch) -> some View {
        frame(minWidth: size, minHeight: size)
            .contentShape(Rectangle())
    }

    /// Prefer this over `.buttonStyle(.plain)` for interactive controls.
    func mimiPressable() -> some View {
        buttonStyle(MimiPressableButtonStyle())
    }

    /// Amounts that must stay readable under Dynamic Type / narrow layouts.
    func mimiAmountFit(lines: Int = 1) -> some View {
        lineLimit(lines)
            .minimumScaleFactor(0.7)
    }
}
