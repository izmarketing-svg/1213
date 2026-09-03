#if os(macOS)
import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotchWorkSettingsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case general = "Основные", blocks = "Панель", integrations = "Интеграции", projects = "Проекты"
        var id: String { rawValue }
        var icon: String { switch self { case .general: "gear"; case .blocks: "rectangle.topthird.inset.filled"; case .integrations: "link"; case .projects: "folder" } }
    }

    @ObservedObject var store: WorkdayStore
    let reminders: RemindersService
    let appleCalendar: AppleCalendarService
    let googleCalendar: GoogleCalendarService
    @State private var selectedPage: Page = .general
    @State private var loginError: String?
    @State private var integrationMessage: String?
    @State private var reminderLists: [ReminderListOption] = []
    @State private var appleCalendars: [CalendarOption] = []
    @State private var workspaceURL = ""
    @State private var isConnectingGoogle = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Раздел настроек", selection: $selectedPage) {
                ForEach(Page.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().padding(16)
            Divider()
            ScrollView {
                Group {
                    switch selectedPage {
                    case .general: generalPage
                    case .blocks: blocksPage
                    case .integrations: integrationsPage
                    case .projects: projectsPage
                    }
                }
                .frame(maxWidth: 680, alignment: .topLeading).padding(20)
            }
        }
        .frame(minWidth: 560, idealWidth: 680, minHeight: 480, idealHeight: 650)
        .task { await reloadIntegrationOptions() }
        .onChange(of: store.settings.appleCalendarEnabled) { _, enabled in
            if enabled { Task { appleCalendars = await appleCalendar.calendars() } }
        }
        .onChange(of: store.settings.remindersIntegrationEnabled) { _, enabled in
            if enabled { Task { reminderLists = await reminders.listOptions() } }
        }
    }

    private var generalPage: some View {
        Form {
            Section("Поведение") {
                Toggle("Запускать при входе в macOS", isOn: binding(\.launchAtLogin) { value in
                    do { try LoginItemService.setEnabled(value) } catch { loginError = error.localizedDescription }
                })
                Toggle("Раскрывать при наведении", isOn: binding(\.opensOnHover))
                Toggle("Показывать поверх полноэкранных приложений", isOn: binding(\.showOverFullScreen))
                Picker("Экран", selection: binding(\.preferredScreenName)) {
                    Text("Автоматически").tag(String?.none)
                    ForEach(NSScreen.screens.map(\.localizedName), id: \.self) { Text($0).tag(String?.some($0)) }
                }
            }
            Section("Рабочий день") {
                Toggle("Автоматически планировать Capture", isOn: binding(\.automaticallyPlanCaptures))
                Stepper("Дедлайн Capture: +\(store.settings.captureDefaultOffsetDays) дн.",
                        value: binding(\.captureDefaultOffsetDays), in: 0...7)
                Picker("Back to Work", selection: binding(\.backToWorkMinutes)) {
                    Text("Выключено").tag(Int?.none)
                    ForEach([10, 15, 20, 30], id: \.self) { Text("Через \($0) минут").tag(Int?.some($0)) }
                }
                Stepper("Pomodoro: \(store.settings.pomodoroWorkMinutes) мин.", value: binding(\.pomodoroWorkMinutes), in: 5...90, step: 5)
                Stepper("Перерыв: \(store.settings.pomodoroBreakMinutes) мин.", value: binding(\.pomodoroBreakMinutes), in: 1...30)
            }
            Section("Горячие клавиши") {
                shortcutPicker("Панель", keyPath: \.togglePanelKey)
                shortcutPicker("Capture", keyPath: \.captureKey)
                shortcutPicker("Проекты", keyPath: \.projectsKey)
                shortcutPicker("Пауза / продолжить", keyPath: \.pauseResumeKey)
            }
            if let loginError { Text(loginError).foregroundStyle(.red).font(.caption) }
        }.formStyle(.grouped)
    }

    private var blocksPage: some View {
        Form {
            Section("Состав панели") {
                Text("Оставьте только те блоки, которыми действительно пользуетесь. NOW — обязательное ядро рабочего дня.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(PanelBlock.allCases) { block in
                    Toggle(block.title, isOn: blockBinding(block)).disabled(block == .now || (block == .calendar && !calendarIsEnabled))
                }
            }
            Section("Приватность буфера") {
                Text("CLIPBOARD выключен по умолчанию. При включении локально сохраняются до 25 текстовых значений. macOS не сообщает надёжно, является ли скопированный текст паролем.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Очистить историю буфера", action: store.clearClipboardHistory).disabled(store.clipboardItems.isEmpty)
            }
        }.formStyle(.grouped)
    }

    private var integrationsPage: some View {
        Form {
            Section("Apple Reminders") {
                Toggle("Создавать и синхронизировать напоминания", isOn: binding(\.remindersIntegrationEnabled))
                if store.settings.remindersIntegrationEnabled {
                    Picker("Список", selection: binding(\.remindersListIdentifier)) {
                        Text("По умолчанию").tag(String?.none)
                        ForEach(reminderLists) { Text($0.title).tag(String?.some($0.id)) }
                    }
                }
            }
            Section("Apple Calendar") {
                Toggle("Показывать события Apple Calendar", isOn: binding(\.appleCalendarEnabled))
                if store.settings.appleCalendarEnabled {
                    if appleCalendars.isEmpty { Text("Нет доступных календарей или доступ не предоставлен.").foregroundStyle(.secondary) }
                    ForEach(appleCalendars) { calendar in
                        Toggle(calendar.title, isOn: setBinding(\.selectedAppleCalendarIDs, value: calendar.id))
                    }
                }
            }
            Section("Google Calendar") {
                Toggle("Показывать Google Calendar", isOn: binding(\.googleCalendarEnabled))
                if store.settings.googleCalendarEnabled {
                    TextField("OAuth Client ID", text: binding(\.googleCalendarClientID))
                    Text("Для личной сборки создайте OAuth Client ID типа Desktop в Google Cloud Console. Redirect URI: app.notchwork.personal:/oauth/google. Секрет клиента не используется; токен хранится в Keychain.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(googleCalendar.isConnected ? "Переподключить" : "Подключить Google") { connectGoogle() }
                            .disabled(store.settings.googleCalendarClientID.isEmpty || isConnectingGoogle)
                        if googleCalendar.isConnected { Button("Отключить", role: .destructive) { googleCalendar.disconnect(); integrationMessage = "Google Calendar отключён." } }
                        if isConnectingGoogle { ProgressView().controlSize(.small) }
                    }
                }
            }
            Section("Уведомления") {
                Toggle("Возврат Waiting", isOn: binding(\.waitingNotifications))
                Toggle("Задачи с конкретным сроком", isOn: binding(\.deadlineNotifications))
                Toggle("Back to Work", isOn: binding(\.backToWorkNotifications))
            }
            if let integrationMessage { Text(integrationMessage).font(.caption).foregroundStyle(.secondary) }
        }.formStyle(.grouped)
    }

    private var projectsPage: some View {
        Form {
            Section("Текущий проект") {
                Picker("Проект", selection: Binding(get: { store.currentProjectID }, set: store.selectProject)) {
                    Text("Без проекта").tag(UUID?.none)
                    ForEach(store.projects) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            }
            if let projectID = store.currentProjectID {
                Section("Название и иконка") {
                    TextField("Название", text: projectNameBinding(projectID))
                    Picker("Иконка", selection: projectIconBinding(projectID)) {
                        ForEach(["folder.fill", "briefcase.fill", "person.fill", "graduationcap.fill", "heart.fill", "star.fill"], id: \.self) {
                            Label($0, systemImage: $0).tag($0)
                        }
                    }
                }
                Section("Workspace") {
                    ForEach(store.resources(for: projectID)) { resource in
                        HStack { Image(systemName: icon(for: resource.kind)); Text(resource.title); Spacer()
                            Button { store.removeResource(resource.id, from: projectID) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                        }
                    }
                    HStack { TextField("https://…", text: $workspaceURL); Button("Добавить URL") { addURL(to: projectID) }.disabled(URL(string: workspaceURL)?.scheme == nil) }
                    HStack {
                        Button("Добавить приложение…") { chooseResource(kind: .application, projectID: projectID) }
                        Button("Добавить папку…") { chooseResource(kind: .folder, projectID: projectID) }
                    }
                }
                Section { Button("Удалить текущий проект", role: .destructive) { store.deleteProject(projectID) } }
            }
        }.formStyle(.grouped)
    }

    private var calendarIsEnabled: Bool { store.settings.appleCalendarEnabled || store.settings.googleCalendarEnabled }

    private func reloadIntegrationOptions() async {
        if store.settings.remindersIntegrationEnabled { reminderLists = await reminders.listOptions() }
        if store.settings.appleCalendarEnabled { appleCalendars = await appleCalendar.calendars() }
    }
    private func connectGoogle() {
        isConnectingGoogle = true; integrationMessage = nil
        Task {
            do { try await googleCalendar.connect(clientID: store.settings.googleCalendarClientID); integrationMessage = "Google Calendar подключён." }
            catch { integrationMessage = error.localizedDescription }
            isConnectingGoogle = false
        }
    }
    private func blockBinding(_ block: PanelBlock) -> Binding<Bool> {
        Binding(get: { store.settings.enabledBlocks.contains(block) }, set: { enabled in
            store.updateSettings {
                if enabled { $0.enabledBlocks.insert(block) } else { $0.enabledBlocks.remove(block) }
                if block == .clipboard { $0.clipboardEnabled = enabled }
                $0.enabledBlocks.insert(.now)
            }
        })
    }
    private func setBinding(_ keyPath: WritableKeyPath<UserSettings, Set<String>>, value: String) -> Binding<Bool> {
        Binding(get: { store.settings[keyPath: keyPath].contains(value) }, set: { enabled in
            store.updateSettings { if enabled { $0[keyPath: keyPath].insert(value) } else { $0[keyPath: keyPath].remove(value) } }
        })
    }
    private func addURL(to projectID: UUID) {
        guard let url = URL(string: workspaceURL), let scheme = url.scheme, ["http", "https"].contains(scheme) else { return }
        store.addResource(WorkspaceResource(title: url.host ?? url.absoluteString, location: url, kind: .url), to: projectID); workspaceURL = ""
    }
    private func chooseResource(kind: WorkspaceResourceKind, projectID: UUID) {
        let panel = NSOpenPanel(); panel.canChooseDirectories = kind == .folder; panel.canChooseFiles = kind == .application
        panel.allowsMultipleSelection = false; if kind == .application { panel.allowedContentTypes = [.applicationBundle] }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.addResource(WorkspaceResource(title: url.deletingPathExtension().lastPathComponent, location: url, kind: kind), to: projectID)
    }
    private func icon(for kind: WorkspaceResourceKind) -> String { switch kind { case .url: "link"; case .application: "app"; case .folder: "folder" } }
    private func projectNameBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { store.projects.first(where: { $0.id == id })?.name ?? "" }, set: { value in
            let icon = store.projects.first(where: { $0.id == id })?.icon ?? "folder.fill"
            store.updateProject(id, name: value, icon: icon)
        })
    }
    private func projectIconBinding(_ id: UUID) -> Binding<String> {
        Binding(get: { store.projects.first(where: { $0.id == id })?.icon ?? "folder.fill" }, set: { value in
            let name = store.projects.first(where: { $0.id == id })?.name ?? "Проект"
            store.updateProject(id, name: name, icon: value)
        })
    }
    private func binding<Value>(_ keyPath: WritableKeyPath<UserSettings, Value>, afterChange: ((Value) -> Void)? = nil) -> Binding<Value> {
        Binding(get: { store.settings[keyPath: keyPath] }, set: { value in store.updateSettings { $0[keyPath: keyPath] = value }; afterChange?(value) })
    }
    private func shortcutPicker(_ title: String, keyPath: WritableKeyPath<UserSettings, String>) -> some View {
        Picker(title, selection: binding(keyPath)) {
            ForEach(Array("abcdefghijklmnopqrstuvwxyz").map(String.init) + [" "], id: \.self) { key in
                Text(key == " " ? "⌘⇧Space" : "⌘⇧\(key.uppercased())").tag(key)
                    .disabled(usedShortcutKeys(excluding: keyPath).contains(key))
            }
        }
    }
    private func usedShortcutKeys(excluding keyPath: WritableKeyPath<UserSettings, String>) -> Set<String> {
        let paths: [WritableKeyPath<UserSettings, String>] = [\.togglePanelKey, \.captureKey, \.projectsKey, \.pauseResumeKey]
        return Set(paths.filter { $0 != keyPath }.map { store.settings[keyPath: $0] })
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    init(store: WorkdayStore, reminders: RemindersService, appleCalendar: AppleCalendarService, googleCalendar: GoogleCalendarService) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 650),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Настройки Notch Work"; window.minSize = NSSize(width: 560, height: 480)
        window.contentView = NSHostingView(rootView: NotchWorkSettingsView(store: store, reminders: reminders,
                                                                           appleCalendar: appleCalendar, googleCalendar: googleCalendar))
        window.center(); super.init(window: window)
    }
    required init?(coder: NSCoder) { nil }
    func present() { showWindow(nil); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
}
#endif
