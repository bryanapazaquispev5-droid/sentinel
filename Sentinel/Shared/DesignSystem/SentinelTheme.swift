import SwiftUI

enum SentinelTheme {
    static let primary = Color(red: 0.08, green: 0.82, blue: 0.72)
    static let primaryDark = Color(red: 0.025, green: 0.055, blue: 0.10)
    static let accent = Color(red: 1.0, green: 0.36, blue: 0.19)
    static let surface = Color(uiColor: .secondarySystemBackground)
    static let success = Color(red: 0.12, green: 0.62, blue: 0.48)
    static let background = Color(uiColor: .systemBackground)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let fieldBackground = Color(uiColor: .secondarySystemBackground)
    static let border = Color(uiColor: .separator)
}

struct SentinelBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(colors: backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(alignment: .topTrailing) {
                Circle().fill(circleColor).frame(width: 260, height: 260).offset(x: 90, y: -80)
            }
    }

    private var backgroundColors: [Color] {
        colorScheme == .dark
            ? [SentinelTheme.primaryDark, Color(red: 0.04, green: 0.12, blue: 0.19)]
            : [Color(red: 0.91, green: 0.96, blue: 0.97), Color(red: 0.98, green: 0.99, blue: 0.98)]
    }

    private var circleColor: Color {
        colorScheme == .dark ? SentinelTheme.accent.opacity(0.12) : SentinelTheme.primary.opacity(0.07)
    }
}

extension View {
    func sentinelPrimaryButton() -> some View {
        self.font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 54)
            .background(LinearGradient(colors: [SentinelTheme.primary, Color(red: 0.02, green: 0.58, blue: 0.65)], startPoint: .leading, endPoint: .trailing)).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    func sentinelSecondaryButton() -> some View {
        modifier(SentinelSecondaryButtonModifier())
    }
}

private struct SentinelSecondaryButtonModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(colorScheme == .dark ? Color.white : SentinelTheme.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(colorScheme == .dark ? Color.white.opacity(0.55) : SentinelTheme.primary.opacity(0.32), lineWidth: 1)
            }
    }
}
