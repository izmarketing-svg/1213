#if os(macOS)
import AppKit
import EventKit
import ServiceManagement
import UserNotifications

@MainActor
final class RemindersService {
    private let store = EKEventStore()

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    func lists() async -> [EKCalendar] {
        guard await requestAccess() else { return [] }
        return store.calendars(for: .reminder)
    }

    func create(for task: WorkTask, listIdentifier: String?) async -> String? {
        guard await requestAccess() else { return nil }
        let reminder = EKReminder(eventStore: store)
        reminder.title = task.title
        reminder.calendar = listIdentifier.flatMap(store.calendar(withIdentifier:)) ?? store.defaultCalendarForNewReminders()
        if let due = task.dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: due)
        }
        do { try store.save(reminder, commit: true); return reminder.calendarItemIdentifier } catch { return nil }
    }

    func setCompleted(identifier: String, completed: Bool) {
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        reminder.isCompleted = completed
        try? store.save(reminder, commit: true)
    }

    func fetch(listIdentifier: String?) async -> [ReminderRecord]? {
        guard await requestAccess() else { return nil }
        let calendars = listIdentifier.flatMap(store.calendar(withIdentifier:)).map { [$0] }
        let predicate = store.predicateForReminders(in: calendars)
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map { reminder in
                    ReminderRecord(identifier: reminder.calendarItemIdentifier,
                                   title: reminder.title,
                                   dueDate: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
                                   isCompleted: reminder.isCompleted,
                                   listIdentifier: reminder.calendar.calendarIdentifier)
                })
            }
        }
    }
}

struct ReminderRecord: Sendable {
    var identifier: String
    var title: String
    var dueDate: Date?
    var isCompleted: Bool
    var listIdentifier: String
}

struct ReminderListOption: Identifiable, Hashable {
    var id: String
    var title: String
}

extension RemindersService {
    func listOptions() async -> [ReminderListOption] {
        await lists().map { ReminderListOption(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

@MainActor
final class NotificationService {
    func requestAccess() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    func scheduleWaiting(_ item: WaitingItem) {
        let content = UNMutableNotificationContent()
        content.title = "Проверить ожидание"
        content.body = [item.title, item.person].compactMap { $0 }.joined(separator: " · ")
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour], from: item.returnDate)
        let request = UNNotificationRequest(identifier: "waiting-\(item.id)", content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        UNUserNotificationCenter.current().add(request)
    }

    func cancelWaiting(_ item: WaitingItem) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["waiting-\(item.id)"])
    }

    func synchronizeWaiting(_ item: WaitingItem) {
        cancelWaiting(item)
        if item.status == .waiting { scheduleWaiting(item) }
    }

    func scheduleDeadline(for task: WorkTask) {
        guard let dueDate = task.dueDate, dueDate > .now else { return }
        let content = UNMutableNotificationContent()
        content.title = "Срок задачи"
        content.body = task.title
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "deadline-\(task.id)", content: content, trigger: trigger))
    }

    func showBackToWork(task: WorkTask) {
        let content = UNMutableNotificationContent()
        content.title = "Вы работали над"
        content.body = task.title
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "back-to-work-\(task.id)", content: content, trigger: nil))
    }
}

@MainActor
final class GlobalShortcutMonitor {
    enum Action { case togglePanel, capture, projects, pauseResume }
    var handler: ((Action) -> Void)?
    var settingsProvider: (() -> UserSettings)?
    private var monitor: Any?

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.contains(.command), flags.contains(.shift) else { return }
            guard let settings = self?.settingsProvider?(), let key = event.charactersIgnoringModifiers?.lowercased() else { return }
            let action: Action? = key == settings.togglePanelKey ? .togglePanel
                : key == settings.captureKey ? .capture
                : key == settings.projectsKey ? .projects
                : key == settings.pauseResumeKey ? .pauseResume : nil
            if let action { Task { @MainActor in self?.handler?(action) } }
        }
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

enum LoginItemService {
    static func setEnabled(_ enabled: Bool) throws {
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

@MainActor
final class ClipboardMonitor {
    var onText: ((String) -> Void)?
    private var timer: Timer?
    private var lastChangeCount = NSPasteboard.general.changeCount

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func poll() {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount
        guard let text = pasteboard.string(forType: .string) else { return }
        onText?(text)
    }

    deinit { timer?.invalidate() }
}

@MainActor
final class BackToWorkMonitor {
    private weak var store: WorkdayStore?
    private var observer: Any?
    private var timer: Timer?
    private var awaySince: Date?
    private var lastReminder: Date?

    func start(store: WorkdayStore) {
        self.store = store
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.evaluateActiveApplication() } }
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluateReminder() }
        }
    }

    private func evaluateActiveApplication() {
        guard let store, store.activeTask != nil, let projectID = store.currentProjectID else { awaySince = nil; return }
        let expected = Set(store.resources(for: projectID).filter { $0.kind == .application }
            .compactMap { Bundle(url: $0.location)?.bundleIdentifier })
        guard !expected.isEmpty else { awaySince = nil; return }
        let activeID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        if activeID.map(expected.contains) == true { awaySince = nil } else if awaySince == nil { awaySince = .now }
    }

    private func evaluateReminder() {
        guard let store, let minutes = store.settings.backToWorkMinutes, let awaySince,
              Date.now.timeIntervalSince(awaySince) >= Double(minutes * 60) else { return }
        if let lastReminder, Date.now.timeIntervalSince(lastReminder) < Double(minutes * 60) { return }
        lastReminder = .now
        store.showBackToWorkSuggestion()
    }

    deinit {
        timer?.invalidate()
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}
#endif
