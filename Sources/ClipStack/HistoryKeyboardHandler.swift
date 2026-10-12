import AppKit
import SwiftUI

/// Window-scoped key handling without requiring a SwiftUI list to own focus.
struct HistoryKeyboardHandler: NSViewRepresentable {
    let handle: (NSEvent, Bool) -> Bool

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.handle = handle
        return view
    }

    func updateNSView(_ view: KeyView, context: Context) { view.handle = handle }

    static func dismantleNSView(_ view: KeyView, coordinator: ()) { view.stop() }

    final class KeyView: NSView {
        var handle: ((NSEvent, Bool) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, let window = self.window,
                      window.isKeyWindow, event.window === window,
                      window.attachedSheet == nil else { return event }
                let editing = (window.firstResponder as? NSTextView)?.isEditable == true
                return self.handle?(event, editing) == true ? nil : event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
