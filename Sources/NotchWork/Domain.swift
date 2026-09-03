import Foundation

enum TaskStatus: String, Codable, CaseIterable, Sendable {
    case inbox, planned, next, active, paused, waiting, done
}

struct Project: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var icon: String = "folder.fill"
    var workspaceURLs: [URL] = []
    var workspaceApplications: [URL] = []
}

enum WorkspaceResourceKind: String, Codable, CaseIterable, Sendable {
    case url, application, folder
}

struct WorkspaceResource: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var location: URL
    var kind: WorkspaceResourceKind
}

struct WorkSession: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var startedAt: Date
    var finishedAt: Date?

    func duration(at date: Date = .now) -> TimeInterval {
        max(0, (finishedAt ?? date).timeIntervalSince(startedAt))
    }

    func duration(on day: Date, now: Date = .now, calendar: Calendar = .current) -> TimeInterval {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return 0 }
        let overlapStart = max(startedAt, dayStart)
        let overlapEnd = min(finishedAt ?? now, dayEnd)
        return max(0, overlapEnd.timeIntervalSince(overlapStart))
    }
}

struct WorkTask: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var projectID: UUID?
    var status: TaskStatus = .inbox
    var createdAt: Date = .now
    var dueDate: Date?
    var plannedDate: Date?
    var order: Int = 0
    var reminderIdentifier: String?
    var reminderListIdentifier: String?
    var sessions: [WorkSession] = []
    var completedAt: Date?

    func totalDuration(at date: Date = .now) -> TimeInterval {
        sessions.reduce(0) { $0 + $1.duration(at: date) }
    }


    func duration(on day: Date, now: Date = .now, calendar: Calendar = .current) -> TimeInterval {
        sessions.reduce(0) { $0 + $1.duration(on: day, now: now, calendar: calendar) }
    }
}

enum WaitingStatus: String, Codable, Sendable { case waiting, received, convertedToTask }

struct WaitingItem: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var title: String
    var person: String?
    var projectID: UUID?
    var createdAt: Date = .now
    var returnDate: Date
    var comment: String?
    var status: WaitingStatus = .waiting
}

struct DailyPlan: Identifiable, Codable, Hashable, Sendable {
    var id: Date { date }
    var date: Date
    var orderedTaskIDs: [UUID]
    var createdAt: Date = .now
    var isConfirmed = false
}

enum PanelBlock: String, Codable, CaseIterable, Identifiable, Sendable {
    case now, next, capture, waiting, projects, done, tomorrow, calendar, clipboard, pomodoro, equalizer
    var id: String { rawValue }
    var title: String {
        switch self {
        case .now: "NOW"
        case .next: "NEXT"
        case .capture: "CAPTURE"
        case .waiting: "WAITING"
        case .projects: "PROJECTS"
        case .done: "DONE TODAY"
        case .tomorrow: "TODAY / TOMORROW"
        case .calendar: "CALENDAR"
        case .clipboard: "CLIPBOARD"
        case .pomodoro: "POMODORO"
        case .equalizer: "FOCUS EQUALIZER"
        }
    }
}

struct UserSettings: Codable, Hashable, Sendable {
    private enum CodingKeys: String, CodingKey {
        case launchAtLogin, opensOnHover, showOverFullScreen, preferredScreenName
        case remindersListIdentifier, captureDefaultOffsetDays, automaticallyPlanCaptures
        case backToWorkMinutes, waitingNotifications, deadlineNotifications
        case backToWorkNotifications, remindersIntegrationEnabled, clipboardEnabled, enabledBlocks
        case appleCalendarEnabled, selectedAppleCalendarIDs, googleCalendarEnabled, googleCalendarClientID
        case togglePanelKey, captureKey, projectsKey, pauseResumeKey
        case pomodoroWorkMinutes, pomodoroBreakMinutes
    }
    var launchAtLogin = false
    var opensOnHover = false
    var showOverFullScreen = true
    var preferredScreenName: String?
    var remindersListIdentifier: String?
    var captureDefaultOffsetDays = 1
    var automaticallyPlanCaptures = true
    var backToWorkMinutes: Int? = 15
    var waitingNotifications = true
    var deadlineNotifications = true
    var backToWorkNotifications = false
    var remindersIntegrationEnabled = true
    var clipboardEnabled = false
    var appleCalendarEnabled = false
    var selectedAppleCalendarIDs = Set<String>()
    var googleCalendarEnabled = false
    var googleCalendarClientID = ""
    var togglePanelKey = "n"
    var captureKey = "c"
    var projectsKey = "p"
    var pauseResumeKey = " "
    var pomodoroWorkMinutes = 25
    var pomodoroBreakMinutes = 5
    var enabledBlocks = Set(PanelBlock.allCases.filter { $0 != .clipboard })

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        opensOnHover = try c.decodeIfPresent(Bool.self, forKey: .opensOnHover) ?? false
        showOverFullScreen = try c.decodeIfPresent(Bool.self, forKey: .showOverFullScreen) ?? true
        preferredScreenName = try c.decodeIfPresent(String.self, forKey: .preferredScreenName)
        remindersListIdentifier = try c.decodeIfPresent(String.self, forKey: .remindersListIdentifier)
        captureDefaultOffsetDays = try c.decodeIfPresent(Int.self, forKey: .captureDefaultOffsetDays) ?? 1
        automaticallyPlanCaptures = try c.decodeIfPresent(Bool.self, forKey: .automaticallyPlanCaptures) ?? true
        backToWorkMinutes = c.contains(.backToWorkMinutes) ? try c.decodeIfPresent(Int.self, forKey: .backToWorkMinutes) : 15
        waitingNotifications = try c.decodeIfPresent(Bool.self, forKey: .waitingNotifications) ?? true
        deadlineNotifications = try c.decodeIfPresent(Bool.self, forKey: .deadlineNotifications) ?? true
        backToWorkNotifications = try c.decodeIfPresent(Bool.self, forKey: .backToWorkNotifications) ?? false
        remindersIntegrationEnabled = try c.decodeIfPresent(Bool.self, forKey: .remindersIntegrationEnabled) ?? true
        clipboardEnabled = try c.decodeIfPresent(Bool.self, forKey: .clipboardEnabled) ?? false
        appleCalendarEnabled = try c.decodeIfPresent(Bool.self, forKey: .appleCalendarEnabled) ?? false
        selectedAppleCalendarIDs = try c.decodeIfPresent(Set<String>.self, forKey: .selectedAppleCalendarIDs) ?? []
        googleCalendarEnabled = try c.decodeIfPresent(Bool.self, forKey: .googleCalendarEnabled) ?? false
        googleCalendarClientID = try c.decodeIfPresent(String.self, forKey: .googleCalendarClientID) ?? ""
        togglePanelKey = try c.decodeIfPresent(String.self, forKey: .togglePanelKey) ?? "n"
        captureKey = try c.decodeIfPresent(String.self, forKey: .captureKey) ?? "c"
        projectsKey = try c.decodeIfPresent(String.self, forKey: .projectsKey) ?? "p"
        pauseResumeKey = try c.decodeIfPresent(String.self, forKey: .pauseResumeKey) ?? " "
        pomodoroWorkMinutes = try c.decodeIfPresent(Int.self, forKey: .pomodoroWorkMinutes) ?? 25
        pomodoroBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .pomodoroBreakMinutes) ?? 5
        enabledBlocks = try c.decodeIfPresent(Set<PanelBlock>.self, forKey: .enabledBlocks) ?? Set(PanelBlock.allCases.filter { $0 != .clipboard })
        enabledBlocks.insert(.now)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(launchAtLogin, forKey: .launchAtLogin)
        try c.encode(opensOnHover, forKey: .opensOnHover)
        try c.encode(showOverFullScreen, forKey: .showOverFullScreen)
        try c.encodeIfPresent(preferredScreenName, forKey: .preferredScreenName)
        try c.encodeIfPresent(remindersListIdentifier, forKey: .remindersListIdentifier)
        try c.encode(captureDefaultOffsetDays, forKey: .captureDefaultOffsetDays)
        try c.encode(automaticallyPlanCaptures, forKey: .automaticallyPlanCaptures)
        try c.encode(backToWorkMinutes, forKey: .backToWorkMinutes)
        try c.encode(waitingNotifications, forKey: .waitingNotifications)
        try c.encode(deadlineNotifications, forKey: .deadlineNotifications)
        try c.encode(backToWorkNotifications, forKey: .backToWorkNotifications)
        try c.encode(remindersIntegrationEnabled, forKey: .remindersIntegrationEnabled)
        try c.encode(clipboardEnabled, forKey: .clipboardEnabled)
        try c.encode(appleCalendarEnabled, forKey: .appleCalendarEnabled)
        try c.encode(selectedAppleCalendarIDs, forKey: .selectedAppleCalendarIDs)
        try c.encode(googleCalendarEnabled, forKey: .googleCalendarEnabled)
        try c.encode(googleCalendarClientID, forKey: .googleCalendarClientID)
        try c.encode(togglePanelKey, forKey: .togglePanelKey)
        try c.encode(captureKey, forKey: .captureKey)
        try c.encode(projectsKey, forKey: .projectsKey)
        try c.encode(pauseResumeKey, forKey: .pauseResumeKey)
        try c.encode(pomodoroWorkMinutes, forKey: .pomodoroWorkMinutes)
        try c.encode(pomodoroBreakMinutes, forKey: .pomodoroBreakMinutes)
        try c.encode(enabledBlocks, forKey: .enabledBlocks)
    }
}

struct ClipboardItem: Identifiable, Codable, Hashable, Sendable {
    var id = UUID()
    var text: String
    var createdAt: Date = .now
}

enum CalendarSource: String, Codable, Sendable { case apple, google }

struct CalendarEventItem: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var calendarTitle: String
    var source: CalendarSource
    var meetingURL: URL?
}

struct WorkdaySnapshot: Codable, Sendable {
    var savedAt: Date = .now
    var projects: [Project] = []
    var tasks: [WorkTask] = []
    var currentProjectID: UUID?
    var waitingItems: [WaitingItem] = []
    var dailyPlans: [DailyPlan] = []
    var workspaceResources: [UUID: [WorkspaceResource]] = [:]
    var settings = UserSettings()
    var clipboardItems: [ClipboardItem] = []

    init(savedAt: Date = .now, projects: [Project] = [], tasks: [WorkTask] = [], currentProjectID: UUID? = nil,
         waitingItems: [WaitingItem] = [], dailyPlans: [DailyPlan] = [],
         workspaceResources: [UUID: [WorkspaceResource]] = [:], settings: UserSettings = UserSettings(),
         clipboardItems: [ClipboardItem] = []) {
        self.savedAt = savedAt; self.projects = projects; self.tasks = tasks; self.currentProjectID = currentProjectID
        self.waitingItems = waitingItems; self.dailyPlans = dailyPlans
        self.workspaceResources = workspaceResources; self.settings = settings
        self.clipboardItems = clipboardItems
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? .now
        projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
        tasks = try container.decodeIfPresent([WorkTask].self, forKey: .tasks) ?? []
        currentProjectID = try container.decodeIfPresent(UUID.self, forKey: .currentProjectID)
        waitingItems = try container.decodeIfPresent([WaitingItem].self, forKey: .waitingItems) ?? []
        dailyPlans = try container.decodeIfPresent([DailyPlan].self, forKey: .dailyPlans) ?? []
        workspaceResources = try container.decodeIfPresent([UUID: [WorkspaceResource]].self, forKey: .workspaceResources) ?? [:]
        settings = try container.decodeIfPresent(UserSettings.self, forKey: .settings) ?? UserSettings()
        clipboardItems = try container.decodeIfPresent([ClipboardItem].self, forKey: .clipboardItems) ?? []
    }
}

enum WorkdayTransitionError: Error, Equatable {
    case taskNotFound
    case completedTask
}


struct ParsedCapture: Equatable, Sendable {
    var title: String
    var dueDate: Date
    var usedExplicitDate: Bool
}

enum CaptureDateParser {
    static func parse(_ input: String, now: Date = .now, calendar: Calendar = .current) -> ParsedCapture? {
        let original = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !original.isEmpty else { return nil }
        let lower = original.lowercased()
        var dueDate: Date?
        var matchedRange: Range<String.Index>?
        var dateOmittedYear = false

        let relative: [(String, Int)] = [("послезавтра", 2), ("завтра", 1), ("сегодня", 0)]
        for (token, days) in relative where dueDate == nil {
            if let range = lower.range(of: token) {
                dueDate = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))
                matchedRange = range
            }
        }

        if dueDate == nil {
            let weekdays = ["воскресенье": 1, "понедельник": 2, "вторник": 3, "среду": 4,
                            "среда": 4, "четверг": 5, "пятницу": 6, "пятница": 6, "субботу": 7, "суббота": 7]
            for (word, weekday) in weekdays {
                guard let range = lower.range(of: word) else { continue }
                let current = calendar.component(.weekday, from: now)
                var delta = (weekday - current + 7) % 7
                if delta == 0 { delta = 7 }
                dueDate = calendar.date(byAdding: .day, value: delta, to: calendar.startOfDay(for: now))
                matchedRange = range
                break
            }
        }

        if dueDate == nil, let result = firstMatch(#"\b(\d{1,2})\.(\d{1,2})(?:\.(\d{4}))?\b"#, in: lower) {
            let parts = result.text.split(separator: ".").compactMap { Int($0) }
            if parts.count >= 2 {
                var components = calendar.dateComponents([.year], from: now)
                components.day = parts[0]; components.month = parts[1]
                if parts.count == 3 { components.year = parts[2] }
                if let parsed = calendar.date(from: components) {
                    dueDate = parsed; matchedRange = result.range; dateOmittedYear = parts.count == 2
                }
            }
        }

        if dueDate == nil {
            let months = ["января": 1, "февраля": 2, "марта": 3, "апреля": 4, "мая": 5, "июня": 6,
                          "июля": 7, "августа": 8, "сентября": 9, "октября": 10, "ноября": 11, "декабря": 12]
            for (name, month) in months {
                guard let monthRange = lower.range(of: name) else { continue }
                let prefix = lower[..<monthRange.lowerBound]
                guard let dayMatch = prefix.range(of: #"\d{1,2}\s*$"#, options: .regularExpression),
                      let day = Int(prefix[dayMatch].trimmingCharacters(in: .whitespaces)) else { continue }
                var components = calendar.dateComponents([.year], from: now)
                components.day = day; components.month = month
                if let parsed = calendar.date(from: components) {
                    dueDate = parsed; matchedRange = dayMatch.lowerBound..<monthRange.upperBound; dateOmittedYear = true
                }
                break
            }
        }

        if dateOmittedYear, let date = dueDate, date < calendar.startOfDay(for: now) {
            dueDate = calendar.date(byAdding: .year, value: 1, to: date)
        }

        let explicit = dueDate != nil
        let fallback = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        var title = original
        if let range = matchedRange {
            let startOffset = lower.distance(from: lower.startIndex, to: range.lowerBound)
            let endOffset = lower.distance(from: lower.startIndex, to: range.upperBound)
            let converted = original.index(original.startIndex, offsetBy: startOffset)..<original.index(original.startIndex, offsetBy: endOffset)
            title.removeSubrange(converted)
            title = title.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
        }
        return ParsedCapture(title: title.isEmpty ? original : title, dueDate: dueDate ?? fallback, usedExplicitDate: explicit)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> (text: String, range: Range<String.Index>)? {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return nil }
        return (String(text[range]), range)
    }
}

enum DailyPlanning {
    static func candidates(for date: Date, tasks: [WorkTask], waiting: [WaitingItem], calendar: Calendar = .current) -> [UUID] {
        let day = calendar.startOfDay(for: date)
        return tasks.filter { task in
            guard task.status != .done && task.status != .waiting else { return false }
            if let planned = task.plannedDate, calendar.isDate(planned, inSameDayAs: day) { return true }
            if let due = task.dueDate, calendar.isDate(due, inSameDayAs: day) { return true }
            return task.status == .active || task.status == .paused || task.status == .next
        }.sorted { ($0.order, $0.createdAt) < ($1.order, $1.createdAt) }.map(\.id)
    }

    static func applyConfirmedPlan(_ plan: DailyPlan, to tasks: inout [WorkTask]) {
        for index in tasks.indices where tasks[index].status == .next { tasks[index].status = .planned }
        for (order, id) in plan.orderedTaskIDs.prefix(3).enumerated() {
            guard let index = tasks.firstIndex(where: { $0.id == id && $0.status != .done }) else { continue }
            tasks[index].status = .next
            tasks[index].order = order
            tasks[index].plannedDate = plan.date
        }
    }

    static func tasksReturningFromWaiting(on date: Date, tasks: [WorkTask], waiting: [WaitingItem], calendar: Calendar = .current) -> [WorkTask] {
        waiting.filter { $0.status == .waiting && calendar.isDate($0.returnDate, inSameDayAs: date) }
            .compactMap { item in
                let title = "Проверить: \(item.title)"
                let alreadyExists = tasks.contains {
                    $0.title == title && $0.projectID == item.projectID && $0.plannedDate.map { calendar.isDate($0, inSameDayAs: date) } == true
                }
                return alreadyExists ? nil : WorkTask(title: title, projectID: item.projectID, status: .planned,
                                                       dueDate: date, plannedDate: date)
            }
    }
}

enum WorkdayTransitions {
    static func start(taskID: UUID, in tasks: inout [WorkTask], at date: Date) throws {
        guard let target = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw WorkdayTransitionError.taskNotFound
        }
        guard tasks[target].status != .done else { throw WorkdayTransitionError.completedTask }

        for index in tasks.indices where tasks[index].status == .active {
            closeSession(for: &tasks[index], at: date)
            tasks[index].status = .paused
        }
        tasks[target].status = .active
        if tasks[target].sessions.last?.finishedAt != nil || tasks[target].sessions.isEmpty {
            tasks[target].sessions.append(WorkSession(startedAt: date))
        }
    }

    static func pauseActive(in tasks: inout [WorkTask], at date: Date) {
        for index in tasks.indices where tasks[index].status == .active {
            closeSession(for: &tasks[index], at: date)
            tasks[index].status = .paused
        }
    }

    static func complete(taskID: UUID, in tasks: inout [WorkTask], at date: Date) throws {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else {
            throw WorkdayTransitionError.taskNotFound
        }
        closeSession(for: &tasks[index], at: date)
        tasks[index].status = .done
        tasks[index].completedAt = date
    }

    private static func closeSession(for task: inout WorkTask, at date: Date) {
        guard let last = task.sessions.indices.last, task.sessions[last].finishedAt == nil else { return }
        task.sessions[last].finishedAt = max(date, task.sessions[last].startedAt)
    }
}
