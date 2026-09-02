#if os(macOS)
import AppKit
import Combine
import Foundation

@MainActor
final class WorkdayStore: ObservableObject {
    @Published private(set) var projects: [Project] = []
    @Published private(set) var tasks: [WorkTask] = []
    @Published private(set) var waitingItems: [WaitingItem] = []
    @Published private(set) var dailyPlans: [DailyPlan] = []
    @Published private(set) var workspaceResources: [UUID: [WorkspaceResource]] = [:]
    @Published private(set) var clipboardItems: [ClipboardItem] = []
    @Published private(set) var calendarEvents: [CalendarEventItem] = []
    @Published private(set) var calendarError: String?
    @Published var settings = UserSettings()
    @Published var currentProjectID: UUID?
    @Published var isExpanded = false
    @Published var draftTaskTitle = ""
    @Published private(set) var resumeSuggestionID: UUID?
    @Published private(set) var backToWorkSuggestionID: UUID?

    private let persistenceURL: URL
    private var cancellables: Set<AnyCancellable> = []
    var onTaskCompleted: ((WorkTask) -> Void)?
    var onWaitingCreated: ((WaitingItem) -> Void)?
    var onWaitingChanged: ((WaitingItem) -> Void)?

    init(persistenceURL: URL? = nil) {
        self.persistenceURL = persistenceURL ?? Self.defaultPersistenceURL
        load()
        seedIfNeeded()
        observeSystemPauses()
    }

    var activeTask: WorkTask? { tasks.first { $0.status == .active } }
    var pausedTask: WorkTask? { tasks.first { $0.status == .paused } }
    var currentTask: WorkTask? { activeTask ?? pausedTask }
    var nextTasks: [WorkTask] {
        tasks.filter { $0.status == .next }
            .sorted { $0.order < $1.order }
            .prefix(3).map { $0 }
    }
    var doneToday: [WorkTask] {
        tasks.filter { $0.status == .done && $0.completedAt.map(Calendar.current.isDateInToday) == true }
    }
    var dueWaitingItems: [WaitingItem] {
        waitingItems.filter { $0.status == .waiting && $0.returnDate <= Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))! }
    }
    var todayDuration: TimeInterval { tasks.reduce(0) { $0 + $1.duration(on: .now) } }
    var resumeSuggestion: WorkTask? { resumeSuggestionID.flatMap { id in tasks.first { $0.id == id } } }
    var tomorrowPlanPreview: DailyPlan {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
        return dailyPlans.first(where: { Calendar.current.isDate($0.date, inSameDayAs: tomorrow) })
            ?? DailyPlan(date: tomorrow, orderedTaskIDs: DailyPlanning.candidates(for: tomorrow, tasks: tasks, waiting: waitingItems))
    }

    func project(for task: WorkTask) -> Project? {
        projects.first { $0.id == task.projectID }
    }

    func addTask() {
        let title = draftTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let nextOrder = (tasks.filter { $0.status == .next }.map(\.order).max() ?? -1) + 1
        tasks.append(WorkTask(title: title, projectID: currentProjectID, status: .next, order: nextOrder))
        draftTaskTitle = ""
        save()
    }

    func start(_ task: WorkTask) {
        try? WorkdayTransitions.start(taskID: task.id, in: &tasks, at: .now)
        save()
    }

    func moveNext(_ task: WorkTask, by offset: Int) {
        var queue = tasks.filter { $0.status == .next }.sorted { $0.order < $1.order }
        guard let from = queue.firstIndex(where: { $0.id == task.id }) else { return }
        let to = min(max(0, from + offset), queue.count - 1)
        guard from != to else { return }
        queue.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        for (order, queued) in queue.enumerated() {
            if let index = tasks.firstIndex(where: { $0.id == queued.id }) { tasks[index].order = order }
        }
        save()
    }

    func removeFromNext(_ task: WorkTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].status = .planned; save()
    }

    func togglePause() {
        if activeTask != nil {
            WorkdayTransitions.pauseActive(in: &tasks, at: .now)
        } else if let pausedTask {
            try? WorkdayTransitions.start(taskID: pausedTask.id, in: &tasks, at: .now)
        }
        save()
    }

    func completeCurrent() {
        guard let task = currentTask else { return }
        try? WorkdayTransitions.complete(taskID: task.id, in: &tasks, at: .now)
        if let completed = tasks.first(where: { $0.id == task.id }) { onTaskCompleted?(completed) }
        save()
    }

    @discardableResult
    func capture(_ text: String, now: Date = .now) -> WorkTask? {
        guard let parsed = CaptureDateParser.parse(text, now: now) else { return nil }
        let dueDate = parsed.usedExplicitDate ? parsed.dueDate
            : (Calendar.current.date(byAdding: .day, value: settings.captureDefaultOffsetDays,
                                     to: Calendar.current.startOfDay(for: now)) ?? parsed.dueDate)
        let task = WorkTask(
            title: parsed.title,
            projectID: currentProjectID,
            status: settings.automaticallyPlanCaptures ? .planned : .inbox,
            dueDate: dueDate,
            plannedDate: settings.automaticallyPlanCaptures ? dueDate : nil
        )
        tasks.append(task)
        save()
        return task
    }

    func addWaiting(title: String, person: String?, returnDate: Date) {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let item = WaitingItem(title: clean, person: person?.nilIfBlank, projectID: currentProjectID, returnDate: returnDate)
        waitingItems.append(item)
        onWaitingCreated?(item)
        save()
    }

    func receive(_ item: WaitingItem) {
        updateWaiting(item.id) { $0.status = .received }
    }

    func postpone(_ item: WaitingItem, days: Int) {
        updateWaiting(item.id) { $0.returnDate = Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now }
    }

    func convertToTask(_ item: WaitingItem) {
        tasks.append(WorkTask(title: item.title, projectID: item.projectID, status: .next,
                              order: (tasks.filter { $0.status == .next }.map(\.order).max() ?? -1) + 1))
        updateWaiting(item.id) { $0.status = .convertedToTask }
    }

    func makeTomorrowPlan(now: Date = .now) -> DailyPlan {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        if let existing = dailyPlans.first(where: { Calendar.current.isDate($0.date, inSameDayAs: tomorrow) }) { return existing }
        let plan = DailyPlan(date: tomorrow, orderedTaskIDs: DailyPlanning.candidates(for: tomorrow, tasks: tasks, waiting: waitingItems))
        dailyPlans.append(plan); save(); return plan
    }

    func confirm(_ plan: DailyPlan) {
        if !dailyPlans.contains(where: { $0.id == plan.id }) { dailyPlans.append(plan) }
        guard let index = dailyPlans.firstIndex(where: { $0.id == plan.id }) else { return }
        dailyPlans[index].isConfirmed = true
        DailyPlanning.applyConfirmedPlan(dailyPlans[index], to: &tasks)
        save()
    }

    func resources(for projectID: UUID) -> [WorkspaceResource] { workspaceResources[projectID] ?? [] }

    func addResource(_ resource: WorkspaceResource, to projectID: UUID) {
        workspaceResources[projectID, default: []].append(resource); save()
    }

    func openWorkspace(for projectID: UUID) {
        resources(for: projectID).forEach { NSWorkspace.shared.open($0.location) }
    }

    func updateSettings(_ transform: (inout UserSettings) -> Void) { transform(&settings); save() }

    func recordClipboardText(_ text: String) {
        guard settings.clipboardEnabled else { return }
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 10_000, clipboardItems.first?.text != clean else { return }
        clipboardItems.removeAll { $0.text == clean }
        clipboardItems.insert(ClipboardItem(text: clean), at: 0)
        clipboardItems = Array(clipboardItems.prefix(25)); save()
    }

    func clearClipboardHistory() { clipboardItems.removeAll(); save() }

    func updateCalendarEvents(apple: [CalendarEventItem], google: [CalendarEventItem], error: String? = nil) {
        calendarEvents = (apple + google).sorted { $0.startDate < $1.startDate }
        calendarError = error
    }

    func linkReminder(_ identifier: String, to taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].reminderIdentifier = identifier; save()
    }

    func synchronizeReminders(_ records: [ReminderRecord], now: Date = .now) {
        var changed = false
        for record in records {
            if let index = tasks.firstIndex(where: { $0.reminderIdentifier == record.identifier }) {
                if record.isCompleted && tasks[index].status != .done {
                    try? WorkdayTransitions.complete(taskID: tasks[index].id, in: &tasks, at: now)
                    changed = true
                }
                if !record.isCompleted && tasks[index].status == .done {
                    tasks[index].status = .planned; tasks[index].completedAt = nil; changed = true
                }
                if tasks[index].title != record.title { tasks[index].title = record.title; changed = true }
                if tasks[index].dueDate != record.dueDate { tasks[index].dueDate = record.dueDate; changed = true }
            } else if !record.isCompleted {
                tasks.append(WorkTask(title: record.title, status: .planned, dueDate: record.dueDate,
                                      plannedDate: record.dueDate, reminderIdentifier: record.identifier))
                changed = true
            }
        }
        if changed { save() }
    }

    func addProject(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let project = Project(name: clean)
        projects.append(project)
        currentProjectID = project.id
        save()
    }

    func selectProject(_ id: UUID?) {
        currentProjectID = id
        save()
    }

    func deleteProject(_ id: UUID) {
        projects.removeAll { $0.id == id }
        workspaceResources[id] = nil
        for index in tasks.indices where tasks[index].projectID == id { tasks[index].projectID = nil }
        if currentProjectID == id { currentProjectID = projects.first?.id }
        save()
    }

    func removeResource(_ id: UUID, from projectID: UUID) {
        workspaceResources[projectID]?.removeAll { $0.id == id }; save()
    }

    func elapsed(for task: WorkTask, at date: Date = .now) -> TimeInterval {
        guard let latest = tasks.first(where: { $0.id == task.id }) else { return 0 }
        return latest.totalDuration(at: date)
    }

    func pauseForSystemInterruption() {
        guard let activeTask else { return }
        resumeSuggestionID = activeTask.id
        WorkdayTransitions.pauseActive(in: &tasks, at: .now)
        save()
    }

    func resumeSuggestedTask() {
        guard let id = resumeSuggestionID, let task = tasks.first(where: { $0.id == id }) else { return }
        resumeSuggestionID = nil; start(task)
    }

    func dismissResumeSuggestion() { resumeSuggestionID = nil }
    func showBackToWorkSuggestion() { backToWorkSuggestionID = currentTask?.id; isExpanded = true }
    func continueBackToWork() {
        guard let id = backToWorkSuggestionID, let task = tasks.first(where: { $0.id == id }) else { return }
        backToWorkSuggestionID = nil
        if task.status != .active { start(task) }
    }
    func dismissBackToWork() { backToWorkSuggestionID = nil }
    var backToWorkSuggestion: WorkTask? { backToWorkSuggestionID.flatMap { id in tasks.first { $0.id == id } } }

    func prepareToTerminate() {
        WorkdayTransitions.pauseActive(in: &tasks, at: .now)
        save()
    }

    private func observeSystemPauses() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.publisher(for: name)
                .receive(on: RunLoop.main)
                .sink { [weak self] _ in self?.pauseForSystemInterruption() }
                .store(in: &cancellables)
        }
    }

    private func seedIfNeeded() {
        guard projects.isEmpty else { return }
        let personal = Project(name: "Личное", icon: "person.fill")
        projects = [personal]
        currentProjectID = personal.id
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: persistenceURL),
              let snapshot = try? JSONDecoder().decode(WorkdaySnapshot.self, from: data) else { return }
        projects = snapshot.projects
        tasks = snapshot.tasks
        if tasks.contains(where: { $0.status == .active }) {
            WorkdayTransitions.pauseActive(in: &tasks, at: snapshot.savedAt)
        }
        currentProjectID = snapshot.currentProjectID
        waitingItems = snapshot.waitingItems
        dailyPlans = snapshot.dailyPlans
        workspaceResources = snapshot.workspaceResources
        settings = snapshot.settings
        clipboardItems = snapshot.clipboardItems
    }

    private func save() {
        let snapshot = WorkdaySnapshot(savedAt: .now, projects: projects, tasks: tasks, currentProjectID: currentProjectID,
                                       waitingItems: waitingItems, dailyPlans: dailyPlans,
                                       workspaceResources: workspaceResources, settings: settings,
                                       clipboardItems: clipboardItems)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(
            at: persistenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: persistenceURL, options: .atomic)
    }

    private func updateWaiting(_ id: UUID, transform: (inout WaitingItem) -> Void) {
        guard let index = waitingItems.firstIndex(where: { $0.id == id }) else { return }
        transform(&waitingItems[index]); onWaitingChanged?(waitingItems[index]); save()
    }

    private static var defaultPersistenceURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchWork", isDirectory: true)
            .appendingPathComponent("workday.json")
    }
}


private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
#endif
