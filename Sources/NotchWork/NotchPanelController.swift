#if os(macOS)
import AppKit
import SwiftUI

@MainActor
final class PanelHostingView: NSHostingView<NotchPanelView> {
    let store: WorkdayStore
    init(store: WorkdayStore) {
        self.store = store
        super.init(rootView: NotchPanelView(store: store))
    }
    required init(rootView: NotchPanelView) {
        self.store = rootView.store
        super.init(rootView: rootView)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { if store.settings.opensOnHover { store.isExpanded = true } }
    override func mouseExited(with event: NSEvent) { if store.settings.opensOnHover { store.isExpanded = false } }
}

@MainActor
final class NotchPanelController: NSWindowController {
    private let store: WorkdayStore

    init(store: WorkdayStore) {
        self.store = store
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 42),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary]
        panel.hidesOnDeactivate = false
        panel.contentView = PanelHostingView(store: store)
        super.init(window: panel)
        applySettings()
        position(on: preferredScreen())
    }

    required init?(coder: NSCoder) { nil }

    func toggle() {
        guard let window else { return }
        if window.isVisible { window.orderOut(nil) } else { position(on: preferredScreen()); window.orderFrontRegardless() }
    }

    func refreshSize() {
        guard let window else { return }
        let height: CGFloat = store.isExpanded ? 420 : 42
        let top = window.frame.maxY
        window.setFrame(NSRect(x: window.frame.minX, y: top - height, width: 410, height: height), display: true, animate: true)
    }

    func applySettings() {
        guard let panel = window as? NSPanel else { return }
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary]
        if store.settings.showOverFullScreen { behavior.insert(.fullScreenAuxiliary) }
        panel.collectionBehavior = behavior
        position(on: preferredScreen())
    }

    private func preferredScreen() -> NSScreen {
        if let preferred = store.settings.preferredScreenName,
           let screen = NSScreen.screens.first(where: { $0.localizedName == preferred }) { return screen }
        return NSScreen.screens.first(where: { $0.localizedName.localizedCaseInsensitiveContains("built-in") }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func position(on screen: NSScreen) {
        guard let window else { return }
        let width: CGFloat = 410
        let height: CGFloat = store.isExpanded ? 420 : 42
        window.setFrame(NSRect(x: screen.frame.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height), display: true)
    }
}
#endif
