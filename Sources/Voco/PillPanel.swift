import AppKit
import SwiftUI

@MainActor
final class PillPanel: NSPanel {
    private var presentationScreen: NSScreen?
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init(model: AppModel) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 74, height: 60),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        contentView = NSHostingView(rootView: PillView(model: model))
        model.pillSizeChanged = { [weak self] size in
            guard let self, self.frame.size != size else { return }
            self.setContentSize(size)
            self.position()
        }
        isReleasedWhenClosed = false
        setAccessibilityLabel("Voco dictation")
    }

    func show() {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        presentationScreen = screen
        position()
        orderFrontRegardless()
    }

    private func position() {
        guard let screen = presentationScreen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.minY + 12))
    }
}
