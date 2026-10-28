import SwiftUI

/// Opaque black rounded rectangle with a thin dark-gray outline, shared by all cards.
struct CardBackground: View {
    @Environment(\.widgetScale) private var scale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Constants.FrontCard.cornerRadius * scale, style: .circular)
        shape
            .fill(Constants.Colors.cardBackground)
            // The outline keeps its width at every scale so it never gets blurry.
            .overlay(shape.strokeBorder(Constants.Colors.cardBorder, lineWidth: Constants.FrontCard.borderWidth))
    }
}
