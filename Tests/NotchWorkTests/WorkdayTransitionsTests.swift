import Foundation
import Testing
@testable import NotchWork

struct WorkdayTransitionsTests {
    @Test func startingAnotherTaskPausesThePreviousOne() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let first = WorkTask(title: "First", status: .active, sessions: [WorkSession(startedAt: start)])
        let second = WorkTask(title: "Second", status: .next)
        var tasks = [first, second]

        try WorkdayTransitions.start(taskID: second.id, in: &tasks, at: start.addingTimeInterval(90))

        #expect(tasks[0].status == .paused)
        #expect(tasks[0].sessions[0].duration() == 90)
        #expect(tasks[1].status == .active)
        #expect(tasks[1].sessions.count == 1)
    }

    @Test func completingTaskClosesItsSession() throws {
        let start = Date(timeIntervalSince1970: 2_000)
        let task = WorkTask(title: "Report", status: .active, sessions: [WorkSession(startedAt: start)])
        var tasks = [task]
        let finish = start.addingTimeInterval(120)

        try WorkdayTransitions.complete(taskID: task.id, in: &tasks, at: finish)

        #expect(tasks[0].status == .done)
        #expect(tasks[0].completedAt == finish)
        #expect(tasks[0].totalDuration() == 120)
    }

    @Test func completedTaskCannotRestart() {
        let task = WorkTask(title: "Done", status: .done)
        var tasks = [task]
        #expect(throws: WorkdayTransitionError.completedTask) {
            try WorkdayTransitions.start(taskID: task.id, in: &tasks, at: .now)
        }
    }
}

struct CaptureDateParserTests {
    private let calendar = Calendar(identifier: .gregorian)
    private let now = Date(timeIntervalSince1970: 1_788_307_200) // 2026-09-02 UTC

    @Test func defaultsToTomorrow() throws {
        let parsed = try #require(CaptureDateParser.parse("проверить отчёт", now: now, calendar: calendar))
        #expect(parsed.title == "проверить отчёт")
        #expect(parsed.usedExplicitDate == false)
        #expect(calendar.dateComponents([.day], from: now, to: parsed.dueDate).day == 1)
    }

    @Test func recognizesRelativeRussianDateAndRemovesItFromTitle() throws {
        let parsed = try #require(CaptureDateParser.parse("отправить договор послезавтра", now: now, calendar: calendar))
        #expect(parsed.title == "отправить договор")
        #expect(parsed.usedExplicitDate)
        #expect(calendar.dateComponents([.day], from: now, to: parsed.dueDate).day == 2)
    }

    @Test func recognizesNumericDate() throws {
        let parsed = try #require(CaptureDateParser.parse("написать клиенту 10.09.2026", now: now, calendar: calendar))
        let components = calendar.dateComponents([.year, .month, .day], from: parsed.dueDate)
        #expect(components.year == 2026)
        #expect(components.month == 9)
        #expect(components.day == 10)
    }
}

struct DailyPlanningTests {
    @Test func confirmedPlanMakesOnlyFirstThreeTasksNext() {
        let tasks = (0..<5).map { WorkTask(title: "Task \($0)", status: .planned, order: $0) }
        var mutable = tasks
        let plan = DailyPlan(date: .now, orderedTaskIDs: tasks.map(\.id), isConfirmed: true)
        DailyPlanning.applyConfirmedPlan(plan, to: &mutable)
        #expect(mutable.filter { $0.status == .next }.count == 3)
        #expect(mutable.prefix(3).map(\.status) == [.next, .next, .next])
    }

    @Test func waitingDueTomorrowBecomesAPlannableTaskWithoutDuplicates() {
        let date = Date(timeIntervalSince1970: 1_788_393_600)
        let waiting = WaitingItem(title: "баннеры", person: "Дизайнер", returnDate: date)
        let first = DailyPlanning.tasksReturningFromWaiting(on: date, tasks: [], waiting: [waiting])
        #expect(first.count == 1)
        #expect(first.first?.title == "Проверить: баннеры")
        let second = DailyPlanning.tasksReturningFromWaiting(on: date, tasks: first, waiting: [waiting])
        #expect(second.isEmpty)
    }
}

struct PersistenceMigrationTests {
    @Test func decodesMVP01SnapshotWithoutNewCollections() throws {
        let data = Data(#"{"projects":[],"tasks":[],"currentProjectID":null}"#.utf8)
        let snapshot = try JSONDecoder().decode(WorkdaySnapshot.self, from: data)
        #expect(snapshot.waitingItems.isEmpty)
        #expect(snapshot.dailyPlans.isEmpty)
        #expect(snapshot.workspaceResources.isEmpty)
        #expect(snapshot.settings.captureDefaultOffsetDays == 1)
    }

    @Test func decodesTaskSavedBeforeReminderListTracking() throws {
        let id = UUID()
        let data = Data("{\"id\":\"\(id.uuidString)\",\"title\":\"Old task\",\"status\":\"inbox\",\"createdAt\":0,\"order\":0,\"sessions\":[]}".utf8)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let task = try decoder.decode(WorkTask.self, from: data)
        #expect(task.reminderListIdentifier == nil)
    }


    @Test func preservesDisabledBackToWorkSetting() throws {
        var settings = UserSettings()
        settings.backToWorkMinutes = nil
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.backToWorkMinutes == nil)
    }


    @Test func preservesCalendarAndPanelConfiguration() throws {
        var settings = UserSettings()
        settings.appleCalendarEnabled = true
        settings.selectedAppleCalendarIDs = ["work", "personal"]
        settings.googleCalendarEnabled = true
        settings.googleCalendarClientID = "client.apps.googleusercontent.com"
        settings.captureKey = "k"
        settings.pomodoroWorkMinutes = 50
        settings.pomodoroBreakMinutes = 10
        settings.enabledBlocks.remove(.waiting)
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.appleCalendarEnabled)
        #expect(decoded.selectedAppleCalendarIDs == ["work", "personal"])
        #expect(decoded.googleCalendarEnabled)
        #expect(decoded.captureKey == "k")
        #expect(decoded.pomodoroWorkMinutes == 50)
        #expect(decoded.pomodoroBreakMinutes == 10)
        #expect(decoded.enabledBlocks.contains(.waiting) == false)
        #expect(decoded.enabledBlocks.contains(.now))
    }
}


struct DailyDurationTests {
    @Test func clipsSessionToRequestedCalendarDay() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 1_788_307_200)
        let session = WorkSession(startedAt: day.addingTimeInterval(-3_600),
                                  finishedAt: day.addingTimeInterval(3_600))
        #expect(session.duration(on: day, calendar: calendar) == 3_600)
    }
}
