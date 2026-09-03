#if os(macOS)
import AppKit
import AuthenticationServices
import CryptoKit
import EventKit
import Security

struct CalendarOption: Identifiable, Hashable {
    var id: String
    var title: String
    var colorHex: String
}

@MainActor
final class AppleCalendarService {
    private let store = EKEventStore()

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func calendars() async -> [CalendarOption] {
        guard await requestAccess() else { return [] }
        return store.calendars(for: .event).map {
            CalendarOption(id: $0.calendarIdentifier, title: $0.title, colorHex: $0.cgColor.hexRGB)
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func events(calendarIDs: Set<String>, from start: Date, to end: Date) async -> [CalendarEventItem] {
        guard await requestAccess() else { return [] }
        let selected = store.calendars(for: .event).filter { calendarIDs.isEmpty || calendarIDs.contains($0.calendarIdentifier) }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: selected)
        return store.events(matching: predicate).map { event in
            CalendarEventItem(id: "apple:\(event.eventIdentifier ?? UUID().uuidString)", title: event.title ?? "Без названия",
                              startDate: event.startDate, endDate: event.endDate, isAllDay: event.isAllDay,
                              calendarTitle: event.calendar.title, source: .apple,
                              meetingURL: event.url ?? Self.detectMeetingURL(in: event.notes))
        }
    }

    func saveEvent(identifier: String?, title: String, start: Date, end: Date) async throws {
        guard await requestAccess() else { return }
        let rawID = identifier?.replacingOccurrences(of: "apple:", with: "")
        let event = rawID.flatMap(store.event(withIdentifier:)) ?? EKEvent(eventStore: store)
        event.title = title
        event.startDate = start
        event.endDate = end
        if event.calendar == nil { event.calendar = store.defaultCalendarForNewEvents }
        try store.save(event, span: .thisEvent, commit: true)
    }

    func deleteEvent(identifier: String) async throws {
        guard await requestAccess() else { return }
        let rawID = identifier.replacingOccurrences(of: "apple:", with: "")
        guard let event = store.event(withIdentifier: rawID) else { return }
        try store.remove(event, span: .thisEvent, commit: true)
    }

    private static func detectMeetingURL(in text: String?) -> URL? {
        guard let text, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, range: range).compactMap(\.url)
            .first { ["zoom.us", "meet.google.com", "teams.microsoft.com"].contains($0.host ?? "") }
    }
}

private extension CGColor {
    var hexRGB: String {
        guard let values = components, values.count >= 3 else { return "#808080" }
        return String(format: "#%02X%02X%02X", Int(values[0] * 255), Int(values[1] * 255), Int(values[2] * 255))
    }
}

@MainActor
final class GoogleCalendarService: NSObject, @preconcurrency ASWebAuthenticationPresentationContextProviding {
    enum GoogleError: LocalizedError {
        case missingClientID, invalidResponse, authenticationCancelled
        var errorDescription: String? {
            switch self {
            case .missingClientID: "Укажите Google OAuth Client ID в настройках."
            case .invalidResponse: "Google вернул некорректный ответ."
            case .authenticationCancelled: "Авторизация Google отменена."
            }
        }
    }

    private struct TokenResponse: Decodable { var access_token: String; var expires_in: Double; var refresh_token: String? }
    private struct EventsResponse: Decodable { var items: [GoogleEvent]? }
    private struct CalendarListResponse: Decodable { var items: [GoogleCalendar]? }
    private struct GoogleCalendar: Decodable { var id: String; var summary: String? }
    private struct GoogleEvent: Decodable {
        struct Moment: Decodable { var date: String?; var dateTime: String? }
        var id: String; var summary: String?; var start: Moment; var end: Moment; var htmlLink: String?
        var hangoutLink: String?
    }
    private struct StoredToken: Codable { var accessToken: String; var refreshToken: String?; var expiresAt: Date }

    private var session: ASWebAuthenticationSession?
    private let callbackScheme = "app.notchwork.personal"
    private let keychainAccount = "google-calendar-token"

    var isConnected: Bool { loadToken() != nil }

    func connect(clientID: String) async throws {
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GoogleError.missingClientID }
        let verifier = Self.randomURLSafe(length: 64)
        let state = Self.randomURLSafe(length: 32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: "app.notchwork.personal:/oauth/google"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/calendar.readonly"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        let callback = try await authenticate(url: components.url!)
        let callbackItems = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        guard callbackItems?.first(where: { $0.name == "state" })?.value == state,
              let code = callbackItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleError.invalidResponse
        }
        let token = try await exchange(code: code, verifier: verifier, clientID: clientID)
        try saveToken(token)
    }

    func disconnect() { deleteToken() }

    func events(clientID: String, from start: Date, to end: Date) async throws -> [CalendarEventItem] {
        var token = try await validToken(clientID: clientID)
        token = try await refreshedAfterUnauthorized(token: token, clientID: clientID) { token in
            var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!)
            request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
            return request
        }
        let calendars = try await calendarList(token: token)
        var result: [CalendarEventItem] = []
        for calendar in calendars {
            result += try await events(in: calendar, token: token, from: start, to: end)
        }
        return result.sorted { $0.startDate < $1.startDate }
    }

    private func calendarList(token: StoredToken) async throws -> [GoogleCalendar] {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList")!)
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw GoogleError.invalidResponse }
        return try JSONDecoder().decode(CalendarListResponse.self, from: data).items ?? []
    }

    private func events(in calendar: GoogleCalendar, token: StoredToken, from start: Date, to end: Date) async throws -> [CalendarEventItem] {
        let encodedID = calendar.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? calendar.id
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/\(encodedID)/events")!
        components.queryItems = [URLQueryItem(name: "timeMin", value: start.ISO8601Format()),
                                 URLQueryItem(name: "timeMax", value: end.ISO8601Format()),
                                 URLQueryItem(name: "singleEvents", value: "true"),
                                 URLQueryItem(name: "orderBy", value: "startTime")]
        var request = URLRequest(url: components.url!); request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw GoogleError.invalidResponse }
        let decoded = try JSONDecoder().decode(EventsResponse.self, from: data)
        return (decoded.items ?? []).compactMap { item in
            guard let startDate = Self.date(item.start), let endDate = Self.date(item.end) else { return nil }
            return CalendarEventItem(id: "google:\(item.id)", title: item.summary ?? "Без названия", startDate: startDate,
                                     endDate: endDate, isAllDay: item.start.date != nil, calendarTitle: calendar.summary ?? "Google Calendar",
                                     source: .google, meetingURL: item.hangoutLink.flatMap(URL.init(string:)) ?? item.htmlLink.flatMap(URL.init(string:)))
        }
    }

    private func refreshedAfterUnauthorized(token: StoredToken, clientID: String,
                                            request: (StoredToken) -> URLRequest) async throws -> StoredToken {
        let (_, response) = try await URLSession.shared.data(for: request(token))
        guard (response as? HTTPURLResponse)?.statusCode == 401 else { return token }
        return try await refresh(token: token, clientID: clientID)
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow() }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: error ?? GoogleError.authenticationCancelled) }
            }
            session.presentationContextProvider = self; session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() { continuation.resume(throwing: GoogleError.authenticationCancelled) }
        }
    }

    private func exchange(code: String, verifier: String, clientID: String) async throws -> StoredToken {
        try await tokenRequest(["code": code, "client_id": clientID, "redirect_uri": "app.notchwork.personal:/oauth/google",
                                "grant_type": "authorization_code", "code_verifier": verifier], previousRefreshToken: nil)
    }

    private func refresh(token: StoredToken, clientID: String) async throws -> StoredToken {
        guard let refreshToken = token.refreshToken else { throw GoogleError.invalidResponse }
        let updated = try await tokenRequest(["client_id": clientID, "refresh_token": refreshToken,
                                              "grant_type": "refresh_token"], previousRefreshToken: refreshToken)
        try saveToken(updated); return updated
    }

    private func tokenRequest(_ values: [String: String], previousRefreshToken: String?) async throws -> StoredToken {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"; request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = values.map { "\($0.key.urlEncoded)=\($0.value.urlEncoded)" }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw GoogleError.invalidResponse }
        let value = try JSONDecoder().decode(TokenResponse.self, from: data)
        return StoredToken(accessToken: value.access_token, refreshToken: value.refresh_token ?? previousRefreshToken,
                           expiresAt: .now.addingTimeInterval(value.expires_in - 60))
    }

    private func validToken(clientID: String) async throws -> StoredToken {
        guard let token = loadToken() else { throw GoogleError.authenticationCancelled }
        return token.expiresAt > .now ? token : try await refresh(token: token, clientID: clientID)
    }

    private func saveToken(_ token: StoredToken) throws {
        deleteToken(); let data = try JSONEncoder().encode(token)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Bundle.main.bundleIdentifier ?? "NotchWork",
                                    kSecAttrAccount as String: keychainAccount, kSecValueData as String: data]
        guard SecItemAdd(query as CFDictionary, nil) == errSecSuccess else { throw GoogleError.invalidResponse }
    }
    private func loadToken() -> StoredToken? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Bundle.main.bundleIdentifier ?? "NotchWork",
                                    kSecAttrAccount as String: keychainAccount, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?; guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(StoredToken.self, from: data)
    }
    private func deleteToken() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: Bundle.main.bundleIdentifier ?? "NotchWork",
                                    kSecAttrAccount as String: keychainAccount]
        SecItemDelete(query as CFDictionary)
    }
    private static func randomURLSafe(length: Int) -> String { String((0..<length).compactMap { _ in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~".randomElement() }) }
    private static func date(_ moment: GoogleEvent.Moment) -> Date? {
        if let value = moment.dateTime { return ISO8601DateFormatter().date(from: value) }
        if let value = moment.date { let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.locale = Locale(identifier: "en_US_POSIX"); return formatter.date(from: value) }
        return nil
    }
}

private extension Data {
    func base64URLEncodedString() -> String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
}
private extension String {
    var urlEncoded: String { addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))) ?? self }
}
#endif
