#if os(macOS)
import AppKit
import SwiftUI

struct NotchPanelView: View {
    enum Section: String, CaseIterable { case now = "NOW", focus = "ФОКУС", calendar = "КАЛЕНДАРЬ", waiting = "WAITING", done = "DONE", tomorrow = "ЗАВТРА", clipboard = "БУФЕР" }
    @ObservedObject var store: WorkdayStore
    @State private var now = Date.now
    @State private var newProjectName = ""
    @State private var selectedSection: Section = .now
    @State private var waitingTitle = ""
    @State private var waitingPerson = ""
    @State private var waitingDate = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var calendarDraftID: String?
    @State private var calendarTitle = ""
    @State private var calendarStart = Date.now
    @State private var calendarEnd = Date.now.addingTimeInterval(3600)

    var body: some View {
        VStack(spacing: 0) {
            compactHeader
            if store.isExpanded {
                Divider().opacity(0.25)
                ScrollView { expandedContent }
                    .scrollIndicators(.never)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .foregroundStyle(.white)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: store.isExpanded ? 18 : 13, style: .continuous))
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: store.isExpanded)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now = $0; store.updatePomodoro(now: $0) }
        .onChange(of: store.settings.enabledBlocks) { _, _ in
            if !availableSections.contains(selectedSection) { selectedSection = .now }
        }
    }

    private var compactHeader: some View {
        Button { store.isExpanded.toggle() } label: {
            HStack(spacing: 10) {
                Circle().fill(store.activeTask == nil ? Color.white.opacity(0.35) : .green).frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.currentTask.map(title) ?? "Что делаем?")
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if let task = store.currentTask {
                        Text(format(store.elapsed(for: task, at: now)))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 10)
                Image(systemName: store.isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).frame(height: 42)
        }.buttonStyle(.plain)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Раздел", selection: $selectedSection) {
                ForEach(availableSections, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()

            if let suggestion = store.resumeSuggestion {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Продолжить «\(suggestion.title)»?").font(.subheadline).bold()
                    HStack {
                        Button("Продолжить", action: store.resumeSuggestedTask)
                        Button("Оставить на паузе", action: store.dismissResumeSuggestion)
                    }.buttonStyle(.borderless)
                }.padding(10).background(.blue.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
            }
            if let suggestion = store.backToWorkSuggestion {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Вы работали над: \(suggestion.title)").font(.subheadline).bold()
                    HStack {
                        Button("Продолжить", action: store.continueBackToWork)
                        Button("Закрыть", action: store.dismissBackToWork)
                    }.buttonStyle(.borderless)
                }.padding(10).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            }
            if store.isDayReviewPresented { dayReview }

            switch selectedSection {
            case .now: nowSection
            case .focus: focusSection
            case .calendar: calendarSection
            case .waiting: waitingSection
            case .done: doneSection
            case .tomorrow: tomorrowSection
            case .clipboard: clipboardSection
            }
        }.padding(16).frame(width: 410)
    }

    private var nowSection: some View {
        Group {
            sectionLabel("NOW")
            if let task = store.currentTask {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.project(for: task)?.name ?? "Без проекта").font(.caption).foregroundStyle(.secondary)
                        Text(task.title).font(.headline).lineLimit(2)
                    }
                    Spacer()
                    actionButton(store.activeTask == nil ? "play.fill" : "pause.fill", store.togglePause)
                    actionButton("checkmark", store.completeCurrent)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    sectionLabel("ДОБРОЕ УТРО · ПЛАН НА СЕГОДНЯ")
                    Text("В плане: \(store.tasks.filter { $0.status == .next || ($0.plannedDate.map(Calendar.current.isDateInToday) == true) }.count) задач")
                        .foregroundStyle(.secondary)
                    if let first = store.nextTasks.first {
                        Button("Начать первую: \(first.title)") { store.start(first) }.buttonStyle(.borderedProminent)
                    } else {
                        Text("Добавьте первую задачу в NEXT").foregroundStyle(.secondary)
                    }
                }
            }

            if store.settings.enabledBlocks.contains(.next) {
                sectionLabel("NEXT")
                if store.nextTasks.isEmpty {
                    Text("Очередь пуста").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(store.nextTasks) { task in
                        HStack {
                            Text(store.project(for: task)?.name ?? "—").foregroundStyle(.secondary)
                            Text("·")
                            Text(task.title).lineLimit(1)
                            Spacer()
                            Button { store.moveNext(task, by: -1) } label: { Image(systemName: "chevron.up") }
                            Button { store.moveNext(task, by: 1) } label: { Image(systemName: "chevron.down") }
                            Button { store.removeFromNext(task) } label: { Image(systemName: "xmark") }
                            Button { store.start(task) } label: { Image(systemName: "play.fill") }
                        }.font(.subheadline).buttonStyle(.plain)
                            .draggable(task.id.uuidString)
                            .dropDestination(for: String.self) { values, _ in
                                guard let value = values.first, let sourceID = UUID(uuidString: value) else { return false }
                                store.moveNext(from: sourceID, before: task.id)
                                return true
                            }
                    }
                }
            }

            if store.settings.enabledBlocks.contains(.capture) {
                HStack {
                    TextField("Новая задача", text: $store.draftTaskTitle)
                        .textFieldStyle(.plain).onSubmit(store.addTask)
                    Button(action: store.addTask) { Image(systemName: "plus.circle.fill") }.buttonStyle(.plain)
                }.padding(10).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
            }

            if store.settings.enabledBlocks.contains(.projects) { HStack {
                Menu {
                    Button("Без проекта") { store.selectProject(nil) }
                    ForEach(store.projects) { project in Button(project.name) { store.selectProject(project.id) } }
                } label: {
                    Label(currentProjectName, systemImage: "folder").font(.caption)
                }.menuStyle(.borderlessButton)
                Spacer()
                TextField("Новый проект", text: $newProjectName).textFieldStyle(.plain).frame(width: 105)
                    .onSubmit(addProject)
                Button(action: addProject) { Image(systemName: "plus") }.buttonStyle(.plain)
                if let id = store.currentProjectID, !store.resources(for: id).isEmpty {
                    Button { store.openWorkspace(for: id) } label: { Image(systemName: "arrow.up.forward.app") }
                        .buttonStyle(.plain).help("Открыть workspace")
                }
            }.foregroundStyle(.secondary) }
        }
    }

    private var waitingSection: some View {
        Group {
            sectionLabel("ДОЛЖНО ВЕРНУТЬСЯ")
            if store.dueWaitingItems.isEmpty {
                Text("Сегодня ничего не возвращается").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(store.dueWaitingItems) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title).font(.headline)
                    Text(item.person ?? "Без исполнителя").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Получено") { store.receive(item) }
                        Button("Позже") { store.postpone(item, days: 1) }
                        Button("В задачу") { store.convertToTask(item) }
                    }.buttonStyle(.borderless).font(.caption)
                }.padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            }
            TextField("Что ждём?", text: $waitingTitle).textFieldStyle(.plain)
            HStack {
                TextField("От кого?", text: $waitingPerson).textFieldStyle(.plain)
                Button("Завтра") { addWaiting(days: 1) }
                Button("Через 3 дня") { addWaiting(days: 3) }
            }.font(.caption)
            HStack {
                DatePicker("Вернуть", selection: $waitingDate, displayedComponents: .date)
                    .labelsHidden()
                Button("Выбрать дату") { addWaiting(date: waitingDate) }
            }.font(.caption)
        }
    }

    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if store.settings.enabledBlocks.contains(.pomodoro) {
                sectionLabel(store.pomodoroIsBreak ? "ПЕРЕРЫВ" : "POMODORO")
                HStack {
                    Text(format(store.pomodoroRemaining(at: now))).font(.system(size: 32, weight: .semibold, design: .monospaced))
                    Spacer()
                    actionButton(store.pomodoroEndsAt == nil ? "play.fill" : "pause.fill") { store.togglePomodoro() }
                    actionButton("arrow.counterclockwise", store.resetPomodoro)
                }
            }
            if store.settings.enabledBlocks.contains(.equalizer) {
                sectionLabel("FOCUS EQUALIZER")
                HStack(alignment: .center, spacing: 5) {
                    ForEach(0..<18, id: \.self) { index in
                        let phase = now.timeIntervalSinceReferenceDate * 3 + Double(index) * 0.7
                        Capsule().fill(store.activeTask == nil ? Color.gray : Color.green)
                            .frame(width: 6, height: store.activeTask == nil ? 5 : 8 + abs(sin(phase)) * 34)
                    }
                }.frame(maxWidth: .infinity, minHeight: 46)
                Text("Визуальный индикатор активной фокус-сессии; аудио и микрофон не анализируются.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var calendarSection: some View {
        Group {
            sectionLabel("СЕГОДНЯ И ЗАВТРА")
            if store.calendarEvents.isEmpty { Text(store.calendarError ?? "Нет ближайших событий").foregroundStyle(.secondary) }
            ForEach(store.calendarEvents) { event in
                HStack(spacing: 10) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(event.isAllDay ? "весь день" : event.startDate.formatted(date: .omitted, time: .shortened))
                        Text(event.source == .apple ? "Apple" : "Google").font(.caption2).foregroundStyle(.secondary)
                    }.frame(width: 65)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).lineLimit(2)
                        Text(event.calendarTitle).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let url = event.meetingURL {
                        Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "video.fill") }.buttonStyle(.plain).help("Открыть встречу")
                    }
                    if event.source == .apple {
                        Button { editCalendarEvent(event) } label: { Image(systemName: "pencil") }.buttonStyle(.plain)
                        Button { store.deleteCalendarEvent(id: event.id) } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                    }
                }.padding(.vertical, 4)
            }
            if store.settings.appleCalendarEnabled {
                Divider().opacity(0.2)
                TextField("Название события", text: $calendarTitle).textFieldStyle(.plain)
                HStack {
                    DatePicker("Начало", selection: $calendarStart).labelsHidden()
                    DatePicker("Конец", selection: $calendarEnd).labelsHidden()
                }
                HStack {
                    Button(calendarDraftID == nil ? "Создать событие" : "Сохранить изменения") { saveCalendarDraft() }
                        .disabled(calendarTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || calendarEnd <= calendarStart)
                    if calendarDraftID != nil { Button("Отмена", action: clearCalendarDraft).buttonStyle(.borderless) }
                }
            }
        }
    }

    private var doneSection: some View {
        Group {
            sectionLabel("DONE TODAY · \(store.doneToday.count)")
            if store.doneToday.isEmpty { Text("Пока ничего не завершено").foregroundStyle(.secondary) }
            ForEach(store.doneToday) { task in
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(title(task)).lineLimit(1); Spacer()
                    Text(shortFormat(store.elapsed(for: task))).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
            Divider().opacity(0.2)
            HStack { Text("Работа сегодня"); Spacer(); Text(shortFormat(store.todayDuration)).bold() }
            Button("Завершить день", action: store.finishDay).buttonStyle(.borderedProminent)
        }
    }

    private var tomorrowSection: some View {
        let plan = store.tomorrowPlanPreview
        return Group {
            sectionLabel("ПЛАН НА ЗАВТРА")
            if plan.orderedTaskIDs.isEmpty { Text("Нет запланированных задач").foregroundStyle(.secondary) }
            ForEach(Array(plan.orderedTaskIDs.enumerated()), id: \.element) { offset, id in
                if let task = store.tasks.first(where: { $0.id == id }) {
                    HStack {
                        Text("\(offset + 1).").foregroundStyle(.secondary); Text(title(task)).lineLimit(1); Spacer()
                        Button { movePlanItem(offset, -1) } label: { Image(systemName: "chevron.up") }
                            .disabled(offset == 0)
                        Button { movePlanItem(offset, 1) } label: { Image(systemName: "chevron.down") }
                            .disabled(offset == plan.orderedTaskIDs.count - 1)
                        Button { store.removeTomorrowTask(id) } label: { Image(systemName: "xmark") }
                    }.buttonStyle(.plain)
                }
            }
            Button(plan.isConfirmed ? "План готов" : "Утвердить план") { store.confirm(plan) }
                .buttonStyle(.borderedProminent).disabled(plan.isConfirmed)
        }
    }

    private var dayReview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("ИТОГИ ДНЯ").font(.headline); Spacer(); Button("Закрыть", action: store.closeDayReview).buttonStyle(.borderless) }
            HStack { Text("Выполнено"); Spacer(); Text("\(store.doneToday.count)").bold() }
            HStack { Text("Рабочее время"); Spacer(); Text(shortFormat(store.todayDuration)).bold() }
            HStack { Text("Незавершено"); Spacer(); Text("\(store.tasks.filter { $0.status != .done }.count)").bold() }
            HStack { Text("Waiting на завтра"); Spacer(); Text("\(store.waitingTomorrowCount)").bold() }
            Button("Перейти к плану на завтра") { selectedSection = .tomorrow }
                .buttonStyle(.borderedProminent)
        }.padding(10).background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
    }

    private var clipboardSection: some View {
        Group {
            HStack { sectionLabel("ИСТОРИЯ БУФЕРА"); Spacer(); Button("Очистить", action: store.clearClipboardHistory).buttonStyle(.borderless) }
            if store.clipboardItems.isEmpty { Text("Скопированный текст появится здесь").foregroundStyle(.secondary) }
            ForEach(store.clipboardItems) { item in
                Button {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.text, forType: .string)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.text).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        Text(item.createdAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }.padding(8).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain)
            }
        }
    }

    private var currentProjectName: String {
        store.projects.first { $0.id == store.currentProjectID }?.name ?? "Без проекта"
    }
    private var availableSections: [Section] {
        Section.allCases.filter { section in
            switch section {
            case .now: true
            case .focus: store.settings.enabledBlocks.contains(.pomodoro) || store.settings.enabledBlocks.contains(.equalizer)
            case .calendar: store.settings.enabledBlocks.contains(.calendar) &&
                (store.settings.appleCalendarEnabled || store.settings.googleCalendarEnabled)
            case .waiting: store.settings.enabledBlocks.contains(.waiting)
            case .done: store.settings.enabledBlocks.contains(.done)
            case .tomorrow: store.settings.enabledBlocks.contains(.tomorrow)
            case .clipboard: store.settings.clipboardEnabled && store.settings.enabledBlocks.contains(.clipboard)
            }
        }
    }
    private func addProject() { store.addProject(named: newProjectName); newProjectName = "" }
    private func addWaiting(days: Int) {
        let date = Calendar.current.date(byAdding: .day, value: days, to: .now) ?? .now
        addWaiting(date: date)
    }
    private func addWaiting(date: Date) {
        store.addWaiting(title: waitingTitle, person: waitingPerson, returnDate: date)
        waitingTitle = ""; waitingPerson = ""
    }
    private func movePlanItem(_ offset: Int, _ delta: Int) {
        let destination = offset + delta
        guard destination >= 0 else { return }
        store.moveTomorrowTask(fromOffsets: IndexSet(integer: offset), toOffset: delta > 0 ? destination + 1 : destination)
    }
    private func editCalendarEvent(_ event: CalendarEventItem) {
        calendarDraftID = event.id
        calendarTitle = event.title
        calendarStart = event.startDate
        calendarEnd = event.endDate
    }
    private func saveCalendarDraft() {
        store.saveCalendarEvent(id: calendarDraftID, title: calendarTitle, start: calendarStart, end: calendarEnd)
        clearCalendarDraft()
    }
    private func clearCalendarDraft() {
        calendarDraftID = nil
        calendarTitle = ""
        calendarStart = .now
        calendarEnd = .now.addingTimeInterval(3600)
    }
    private func title(_ task: WorkTask) -> String { [store.project(for: task)?.name, task.title].compactMap { $0 }.joined(separator: " · ") }
    private func format(_ value: TimeInterval) -> String {
        let seconds = max(0, Int(value)); return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
    private func shortFormat(_ value: TimeInterval) -> String {
        let minutes = Int(value) / 60; return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
    private func sectionLabel(_ value: String) -> some View { Text(value).font(.system(size: 10, weight: .bold)).tracking(1.4).foregroundStyle(.secondary) }
    private func actionButton(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 28, height: 28).background(.white.opacity(0.12), in: Circle()) }.buttonStyle(.plain)
    }
}
#endif
