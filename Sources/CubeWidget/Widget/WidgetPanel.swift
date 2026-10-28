import AppKit

/// The widget's window.
///
/// An NSPanel is a lightweight "tool" window: it can float above every other window
/// without stealing the keyboard focus from the app you are typing in.
final class WidgetPanel: NSPanel {
    private var mouseDownLocation: NSPoint?

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating                          // above normal windows
        collectionBehavior = [.canJoinAllSpaces,   // visible on every desktop (Space)
                              .fullScreenAuxiliary,
                              .stationary]         // does not slide when switching Spaces
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear                   // only the cards are drawn
        hasShadow = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Turns a mouse drag anywhere on the widget into a window move,
    /// while a simple click still reaches the cards.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            mouseDownLocation = NSEvent.mouseLocation
        case .leftMouseDragged:
            if let start = mouseDownLocation {
                let now = NSEvent.mouseLocation
                if hypot(now.x - start.x, now.y - start.y) >= Constants.Window.dragThreshold {
                    mouseDownLocation = nil
                    performDrag(with: event)
                    return
                }
            }
        case .leftMouseUp:
            mouseDownLocation = nil
        default:
            break
        }
        super.sendEvent(event)
    }
}
