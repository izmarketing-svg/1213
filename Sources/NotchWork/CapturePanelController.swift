#if os(macOS)
import AppKit
import SwiftUI

struct CaptureView: View {
    @ObservedObject var store: WorkdayStore
    var onSaved: (WorkTask) -> Void
    var onClose: () -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down.fill").foregroundStyle(.secondary)
            TextField("Что не забыть?", text: $text)
                .textFieldStyle(.plain).font(.system(size: 18, weight: .medium))
                .focused($focused).onSubmit(save)
            Text("↵").foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 20).frame(width: 520, height: 62)
        .foregroundStyle(.white).background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear { focused = true }
        .onExitCommand(perform: onClose)
    }

    private func save() {
        guard let task = store.capture(text) else { return }
        onSaved(task); onClose()
    }
}

@MainActor
final class CapturePanelController: NSWindowController {
    init(store: WorkdayStore, onSaved: @escaping (WorkTask) -> Void) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 62),
                            styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        panel.level = .popUpMenu; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        super.init(window: panel)
        panel.contentView = NSHostingView(rootView: CaptureView(store: store, onSaved: onSaved) { [weak self] in self?.close() })
    }
    required init?(coder: NSCoder) { nil }

    func present() {
        guard let window, let screen = NSScreen.main else { return }
        window.setFrameOrigin(NSPoint(x: screen.frame.midX - window.frame.width / 2, y: screen.frame.maxY - 150))
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
