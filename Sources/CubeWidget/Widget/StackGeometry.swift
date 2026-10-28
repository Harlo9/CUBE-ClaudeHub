import CoreGraphics

/// Place of a card in the stack.
enum CardRole: Equatable {
    case front
    /// Card below the front card; 0 is the one right under it.
    case back(Int)

    var isBack: Bool { self != .front }

    /// Drawing order: the front card on top, then each card below under the previous one.
    var zIndex: Double {
        switch self {
        case .front: 20
        case .back(let index): 10 - Double(index)
        }
    }
}

/// Positions of the cards, in points at 100 % scale, from the top-left corner of the front card.
enum StackGeometry {
    private typealias Front = Constants.FrontCard
    private typealias Back = Constants.BackCard

    static func rect(for role: CardRole, collapsed: Bool) -> CGRect {
        if collapsed {
            // Folded: only the square around the cube; the cards below slide under it.
            return CGRect(x: 0, y: 0, width: Front.collapsedSide, height: Front.collapsedSide)
        }
        switch role {
        case .front:
            return CGRect(x: 0, y: 0, width: Front.width, height: Front.height)
        case .back(let index):
            // The card's bottom band sticks out under the card above; the rest is hidden under it.
            let height = Back.visibleHeight + Back.hiddenHeight
            let bottom = Front.height + Back.visibleHeight * CGFloat(index + 1)
            return CGRect(x: 0, y: bottom - height, width: Front.width, height: height)
        }
    }

    /// Size of the whole stack of cards.
    static func size(backCount: Int, collapsed: Bool) -> CGSize {
        if collapsed {
            return CGSize(width: Front.collapsedSide, height: Front.collapsedSide)
        }
        return CGSize(width: Front.width, height: Front.height + Back.visibleHeight * CGFloat(backCount))
    }
}
