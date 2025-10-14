import SwiftUI

#if os(macOS)
import AppKit

struct RightClickOverlay: NSViewRepresentable {
    var onAdd: (CGPoint) -> Void
    var onZoom: (CGPoint) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = RightClickCatcher()
        view.onAdd = onAdd
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class RightClickCatcher: NSView {
        var onAdd: ((CGPoint) -> Void)?
        var onZoom: ((CGPoint) -> Void)?
        private var lastPoint: CGPoint = .zero

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            let recognizer = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
            recognizer.buttonMask = 0x2 // right mouse only
            addGestureRecognizer(recognizer)
            wantsLayer = false
//            isOpaque = false
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        @objc private func handleClick(_ recognizer: NSClickGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            lastPoint = recognizer.location(in: self)
            let menu = NSMenu()
            menu.addItem(withTitle: "Add Place Here", action: #selector(addHere), keyEquivalent: "")
            menu.addItem(withTitle: "Zoom Here", action: #selector(zoomHere), keyEquivalent: "")
            menu.items.forEach { $0.target = self }
            NSMenu.popUpContextMenu(menu, with: NSApp.currentEvent!, for: self)
        }

        // Only participate in hit testing for right-click (or control-click);
        // let all other gestures like pinch/scroll fall through to the map.
        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = window?.currentEvent else { return nil }
            switch event.type {
            case .rightMouseDown, .rightMouseUp:
                return self
            case .leftMouseDown:
                if event.modifierFlags.contains(.control) { return self }
                fallthrough
            default:
                return nil
            }
        }

        @objc private func addHere() { onAdd?(lastPoint) }
        @objc private func zoomHere() { onZoom?(lastPoint) }
    }
}
#endif


