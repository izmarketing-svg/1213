import Foundation
import XCTest
@testable import NotchWork

final class WorkdayTransitionsTests: XCTestCase {
    func testStartingAnotherTaskPausesThePreviousOne() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let first = WorkTask(title: "First", status: .active, sessions: [WorkSession(startedAt: start)])
        let second = WorkTask(title: "Second", status: .next)
        var tasks = [first, second]

        try WorkdayTransitions.start(taskID: second.id, in: &tasks, at: start.addingTimeInterval(90))

        XCTAssertEqual(tasks[0].status, .paused)
        XCTAssertEqual(tasks[0].sessions[0].duration(), 90)
        XCTAssertEqual(tasks[1].status, .active)
        XCTAssertEqual(tasks[1].sessions.count, 1)
    }

    func testCompletingTaskClosesItsSession() throws {
        let start = Date(timeIntervalSince1970: 2_000)
        let task = WorkTask(title: "Report", status: .active, sessions: [WorkSession(startedAt: start)])
        var tasks = [task]
        let finish = start.addingTimeInterval(120)

        try WorkdayTransitions.complete(taskID: task.id, in: &tasks, at: finish)

        XCTAssertEqual(tasks[0].status, .done)
        XCTAssertEqual(tasks[0].completedAt, finish)
        XCTAssertEqual(tasks[0].totalDuration(), 120)
    }

    func testCompletedTaskCannotRestart() {
        let task = WorkTask(title: "Done", status: .done)
        var tasks = [task]
        XCTAssertThrowsError(try WorkdayTransitions.start(taskID: task.id, in: &tasks, at: .now)) { error in
            XCTAssertEqual(error as? WorkdayTransitionError, .completedTask)
        }
    }
}

final class CaptureDateParserTests: XCTestCase {
    private var calendar: Calendar { Calendar(identifier: .gregorian) }
    private let now = Date(timeIntervalSince1970: 1_788_307_200)

    func testDefaultsToTomorrow() throws {
        let parsed = try XCTUnwrap(CaptureDateParser.parse("проверить отчёт", now: now, calendar: calendar))
        XCTAssertEqual(parsed.title, "проверить отчёт")
        XCTAssertFalse(parsed.usedExplicitDate)
        XCTAssertEqual(calendar.dateComponents([.day], from: now, to: parsed.dueDate).day, 1)
    }

    func testRecognizesRelativeRussianDateAndRemovesItFromTitle() throws {
        let parsed = try XCTUnwrap(CaptureDateParser.parse("отправить договор послезавтра", now: now, calendar: calendar))
        XCTAssertEqual(parsed.title, "отправить договор")
        XCTAssertTrue(parsed.usedExplicitDate)
        XCTAssertEqual(calendar.dateComponents([.day], from: now, to: parsed.dueDate).day, 2)
    }

    func testRecognizesNumericDate() throws {
        let parsed = try XCTUnwrap(CaptureDateParser.parse("написать клиенту 10.09.2026", now: now, calendar: calendar))
        let components = calendar.dateComponents([.year, .month, .day], from: parsed.dueDate)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 10)
    }
}

final class DailyPlanningTests: XCTestCase {
    func testConfirmedPlanMakesOnlyFirstThreeTasksNext() {
        let tasks = (0..<5).map { WorkTask(title: "Task \($0)", status: .planned, order: $0) }
        var mutable = tasks
        let plan = DailyPlan(date: .now, orderedTaskIDs: tasks.map(\.id), isConfirmed: true)
        DailyPlanning.applyConfirmedPlan(plan, to: &mutable)
        XCTAssertEqual(mutable.filter { $0.status == .next }.count, 3)
        XCTAssertEqual(mutable.prefix(3).map(\.status), [.next, .next, .next])
    }

    func testWaitingDueTomorrowBecomesAPlannableTaskWithoutDuplicates() {
        let date = Date(timeIntervalSince1970: 1_788_393_600)
        let waiting = WaitingItem(title: "баннеры", person: "Дизайнер", returnDate: date)
        let first = DailyPlanning.tasksReturningFromWaiting(on: date, tasks: [], waiting: [waiting])
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first.first?.title, "Проверить: баннеры")
        let second = DailyPlanning.tasksReturningFromWaiting(on: date, tasks: first, waiting: [waiting])
        XCTAssertTrue(second.isEmpty)
    }
}

final class PersistenceMigrationTests: XCTestCase {
    func testDecodesMVP01SnapshotWithoutNewCollections() throws {
        let data = Data(#"{"projects":[],"tasks":[],"currentProjectID":null}"#.utf8)
        let snapshot = try JSONDecoder().decode(WorkdaySnapshot.self, from: data)
        XCTAssertTrue(snapshot.waitingItems.isEmpty)
        XCTAssertTrue(snapshot.dailyPlans.isEmpty)
        XCTAssertTrue(snapshot.workspaceResources.isEmpty)
        XCTAssertEqual(snapshot.settings.captureDefaultOffsetDays, 1)
    }

    func testDecodesTaskSavedBeforeReminderListTracking() throws {
        let id = UUID()
        let data = Data("{\"id\":\"\(id.uuidString)\",\"title\":\"Old task\",\"status\":\"inbox\",\"createdAt\":0,\"order\":0,\"sessions\":[]}".utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        let task = try decoder.decode(WorkTask.self, from: data)
        XCTAssertNil(task.reminderListIdentifier)
    }

    func testPreservesDisabledBackToWorkSetting() throws {
        var settings = UserSettings()
        settings.backToWorkMinutes = nil
        let decoded = try JSONDecoder().decode(UserSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertNil(decoded.backToWorkMinutes)
    }

    func testPreservesCalendarAndPanelConfiguration() throws {
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
        XCTAssertTrue(decoded.appleCalendarEnabled)
        XCTAssertEqual(decoded.selectedAppleCalendarIDs, ["work", "personal"])
        XCTAssertTrue(decoded.googleCalendarEnabled)
        XCTAssertEqual(decoded.captureKey, "k")
        XCTAssertEqual(decoded.pomodoroWorkMinutes, 50)
        XCTAssertEqual(decoded.pomodoroBreakMinutes, 10)
        XCTAssertFalse(decoded.enabledBlocks.contains(.waiting))
        XCTAssertTrue(decoded.enabledBlocks.contains(.now))
    }
}

final class DailyDurationTests: XCTestCase {
    func testClipsSessionToRequestedCalendarDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 1_788_307_200)
        let session = WorkSession(startedAt: day.addingTimeInterval(-3_600),
                                  finishedAt: day.addingTimeInterval(3_600))
        XCTAssertEqual(session.duration(on: day, calendar: calendar), 3_600)
    }
}
