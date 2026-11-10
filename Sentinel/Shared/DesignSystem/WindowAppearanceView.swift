import SwiftUI
import UIKit

/// Applies the selected app theme to UIKit-backed views such as MapKit.
struct WindowAppearanceView: UIViewRepresentable {
    let theme: AppThemeMode

    func makeUIView(context: Context) -> ThemeWindowView {
        ThemeWindowView(theme: theme)
    }

    func updateUIView(_ view: ThemeWindowView, context: Context) {
        view.theme = theme
        view.applyThemeIfPossible()
    }
}

final class ThemeWindowView: UIView {
    var theme: AppThemeMode

    init(theme: AppThemeMode) {
        self.theme = theme
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = .clear
        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        applyThemeIfPossible()
    }

    func applyThemeIfPossible() {
        window?.overrideUserInterfaceStyle = theme.userInterfaceStyle
    }
}

private extension AppThemeMode {
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}
