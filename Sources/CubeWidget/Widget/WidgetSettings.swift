import SwiftUI

/// User preferences of the widget, saved in UserDefaults.
@MainActor
final class WidgetSettings: ObservableObject {
    private static let scaleKey = "widgetScale"
    private static let collapsedKey = "widgetCollapsed"
    private static let visibleKey = "widgetVisible"

    /// Size multiplier of the whole widget (1 = 100 %).
    @Published var scale: Double {
        didSet { UserDefaults.standard.set(scale, forKey: Self.scaleKey) }
    }

    /// True when the widget is folded down to the cube alone.
    @Published var isCollapsed: Bool {
        didSet { UserDefaults.standard.set(isCollapsed, forKey: Self.collapsedKey) }
    }

    /// "Afficher le widget": shown or hidden (the mini cube stays in the menu bar).
    @Published var isVisible: Bool {
        didSet { UserDefaults.standard.set(isVisible, forKey: Self.visibleKey) }
    }

    init() {
        let saved = UserDefaults.standard.double(forKey: Self.scaleKey)
        // Snap to the closest choice so a slightly rounded saved value is still recognized.
        scale = Constants.Window.scaleChoices.first { abs($0 - saved) < 0.001 } ?? 1
        isCollapsed = UserDefaults.standard.bool(forKey: Self.collapsedKey)
        isVisible = UserDefaults.standard.object(forKey: Self.visibleKey) as? Bool ?? true
    }
}

// MARK: - Scale in the SwiftUI environment

private struct WidgetScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// Multiplier applied by the views to every size from `Constants`.
    var widgetScale: CGFloat {
        get { self[WidgetScaleKey.self] }
        set { self[WidgetScaleKey.self] = newValue }
    }
}
