#if os(macOS)
import AppKit
import Combine

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = WorkdayStore()
    private var panelController: NotchPanelController?
    private var statusItem: NSStatusItem?
    private var captureController: CapturePanelController?
    private var settingsController: SettingsWindowController?
    private let shortcuts = GlobalShortcutMonitor()
    private let reminders = RemindersService()
    private let notifications = NotificationService()
    private let clipboard = ClipboardMonitor()
    private let backToWork = BackToWorkMonitor()
    private let appleCalendar = AppleCalendarService()
    private let googleCalendar = GoogleCalendarService()
    private var cancellables: Set<AnyCancellable> = []
    private var reminderSyncTimer: Timer?
    private var calendarSyncTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let controller = NotchPanelController(store: store)
        panelController = controller
        controller.showWindow(nil)

        store.$isExpanded.dropFirst().sink { [weak controller] _ in
            DispatchQueue.main.async { controller?.refreshSize() }
        }.store(in: &cancellables)
        store.$settings.dropFirst().sink { [weak self, weak controller] settings in
            DispatchQueue.main.async {
                controller?.applySettings()
                if settings.clipboardEnabled { self?.clipboard.start() } else { self?.clipboard.stop() }
                self?.refreshCalendars()
            }
        }.store(in: &cancellables)
        store.$backToWorkSuggestionID.dropFirst().compactMap { $0 }.sink { [weak self] id in
            guard let self, self.store.settings.backToWorkNotifications,
                  let task = self.store.tasks.first(where: { $0.id == id }) else { return }
            self.notifications.showBackToWork(task: task)
        }.store(in: &cancellables)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Notch Work")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Показать / скрыть", action: #selector(togglePanel), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Capture…", action: #selector(showCapture), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Настройки…", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Завершить Notch Work", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        item.menu = menu
        statusItem = item

        shortcuts.handler = { [weak self] action in
            guard let self else { return }
            switch action {
            case .togglePanel, .projects: self.panelController?.toggle()
            case .capture: self.showCapture()
            case .pauseResume: self.store.togglePause()
            }
        }
        shortcuts.settingsProvider = { [weak self] in self?.store.settings ?? UserSettings() }
        shortcuts.start()
        clipboard.onText = { [weak self] text in self?.store.recordClipboardText(text) }
        if store.settings.clipboardEnabled { clipboard.start() }
        backToWork.start(store: store)

        store.onTaskCompleted = { [weak self] task in
            guard let identifier = task.reminderIdentifier else { return }
            self?.reminders.setCompleted(identifier: identifier, completed: true)
        }
        store.onWaitingCreated = { [weak self] item in
            guard self?.store.settings.waitingNotifications == true else { return }
            self?.notifications.scheduleWaiting(item)
        }
        store.onWaitingChanged = { [weak self] item in self?.notifications.synchronizeWaiting(item) }
        store.onSaveCalendarEvent = { [weak self] id, title, start, end in
            guard let self else { return }
            Task { try? await self.appleCalendar.saveEvent(identifier: id, title: title, start: start, end: end); self.refreshCalendars() }
        }
        store.onDeleteCalendarEvent = { [weak self] id in
            guard let self else { return }
            Task { try? await self.appleCalendar.deleteEvent(identifier: id); self.refreshCalendars() }
        }
        if store.settings.waitingNotifications || store.settings.deadlineNotifications {
            Task { await notifications.requestAccess() }
        }
        synchronizeReminders()
        reminderSyncTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.synchronizeReminders() }
        }
        refreshCalendars()
        calendarSyncTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshCalendars() }
        }
    }

    @objc private func togglePanel() { panelController?.toggle() }
    @objc private func showCapture() {
        let controller = CapturePanelController(store: store) { [weak self] task in
            guard let self else { return }
            if self.store.settings.deadlineNotifications { self.notifications.scheduleDeadline(for: task) }
            Task {
                guard self.store.settings.remindersIntegrationEnabled else { return }
                if let identifier = await self.reminders.create(for: task, listIdentifier: self.store.settings.remindersListIdentifier) {
                    self.store.linkReminder(identifier, listIdentifier: self.store.settings.remindersListIdentifier, to: task.id)
                }
            }
        }
        captureController = controller
        controller.present()
    }
    @objc private func showSettings() {
        let controller = settingsController ?? SettingsWindowController(store: store, reminders: reminders,
                                                                         appleCalendar: appleCalendar, googleCalendar: googleCalendar)
        settingsController = controller; controller.present()
    }
    private func synchronizeReminders() {
        guard store.settings.remindersIntegrationEnabled else { return }
        Task {
            let records = await reminders.fetch(listIdentifier: store.settings.remindersListIdentifier)
            if let records { store.synchronizeReminders(records, listIdentifier: store.settings.remindersListIdentifier) }
        }
    }
    private func refreshCalendars() {
        let settings = store.settings
        Task {
            let start = Calendar.current.startOfDay(for: .now)
            let end = Calendar.current.date(byAdding: .day, value: 2, to: start)!
            let apple = settings.appleCalendarEnabled
                ? await appleCalendar.events(calendarIDs: settings.selectedAppleCalendarIDs, from: start, to: end) : []
            var google: [CalendarEventItem] = []; var calendarError: String?
            if settings.googleCalendarEnabled && googleCalendar.isConnected {
                do { google = try await googleCalendar.events(clientID: settings.googleCalendarClientID, from: start, to: end) }
                catch { calendarError = error.localizedDescription }
            }
            store.updateCalendarEvents(apple: apple, google: google, error: calendarError)
        }
    }
    @objc private func quit() { store.prepareToTerminate(); NSApp.terminate(nil) }
}
#else
import Foundation

@main
enum NotchWorkLinuxStub {
    static func main() {
        print("Notch Work is a native macOS application. Build this package on macOS 14 or later.")
    }
}
#endif
