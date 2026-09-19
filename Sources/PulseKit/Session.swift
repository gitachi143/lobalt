import Foundation
import Observation

/// One completed (or abandoned) stretch of timed work.
public struct Session: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let label: String
    /// What you gave yourself.
    public let planned: TimeInterval
    /// What it actually took, overtime included.
    public let actual: TimeInterval
    public let startedAt: Date
    public let endedAt: Date
    /// Whether the timer reached zero, as opposed to being stopped early.
    public let completed: Bool

    public init(id: UUID = UUID(), label: String, planned: TimeInterval,
                actual: TimeInterval, startedAt: Date, endedAt: Date, completed: Bool) {
        self.id = id
        self.label = label
        self.planned = planned
        self.actual = actual
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.completed = completed
    }

    /// >1 means you ran over your estimate, <1 means you came in under.
    public var overrunRatio: Double {
        guard planned > 0 else { return 1 }
        return actual / planned
    }

    public var overrun: TimeInterval { actual - planned }
}

/// Rolled-up numbers for the history panel.
public struct SessionStats: Equatable, Sendable {
    public var count = 0
    public var totalTime: TimeInterval = 0
    /// Mean of `actual / planned` across sessions that reached the bell.
    public var averageOverrun: Double = 1
    public var hasOverrunData = false

    /// "12% over" / "8% under" / "on the money".
    public var overrunDescription: String {
        guard hasOverrunData else { return "—" }
        let pct = Int(((averageOverrun - 1) * 100).rounded())
        if pct == 0 { return "on the money" }
        return pct > 0 ? "\(pct)% over" : "\(-pct)% under"
    }
}

/// Append-only log of sessions, persisted as JSON.
@Observable
public final class SessionStore {

    public private(set) var sessions: [Session] = []

    private let url: URL
    private let limit: Int

    public init(url: URL? = nil, limit: Int = 2000) {
        self.url = url ?? SessionStore.defaultURL()
        self.limit = limit
        load()
    }

    public static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("Pulse", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }

    public func add(_ session: Session) {
        sessions.append(session)
        if sessions.count > limit { sessions.removeFirst(sessions.count - limit) }
        save()
    }

    public func delete(_ session: Session) {
        sessions.removeAll { $0.id == session.id }
        save()
    }

    public func clear() {
        sessions.removeAll()
        save()
    }

    /// Most recent first.
    public var recent: [Session] { sessions.reversed() }

    public func sessions(on day: Date, calendar: Calendar = .current) -> [Session] {
        sessions.filter { calendar.isDate($0.endedAt, inSameDayAs: day) }
    }

    public func stats(for sessions: [Session]) -> SessionStats {
        var s = SessionStats()
        s.count = sessions.count
        s.totalTime = sessions.reduce(0) { $0 + $1.actual }
        // Only completed timers say anything useful about estimation quality;
        // one you stopped early tells you nothing about how long it needed.
        let judged = sessions.filter { $0.completed && $0.planned > 0 }
        if !judged.isEmpty {
            s.averageOverrun = judged.reduce(0.0) { $0 + $1.overrunRatio } / Double(judged.count)
            s.hasOverrunData = true
        }
        return s
    }

    public var today: SessionStats { stats(for: sessions(on: Date())) }
    public var allTime: SessionStats { stats(for: sessions) }

    /// Consecutive days up to today with at least one session.
    public var dayStreak: Int {
        let cal = Calendar.current
        let days = Set(sessions.map { cal.startOfDay(for: $0.endedAt) })
        guard !days.isEmpty else { return 0 }
        var streak = 0
        var cursor = cal.startOfDay(for: Date())
        // Yesterday still counts while today is young.
        if !days.contains(cursor) {
            guard let back = cal.date(byAdding: .day, value: -1, to: cursor), days.contains(back) else { return 0 }
            cursor = back
        }
        while days.contains(cursor) {
            streak += 1
            guard let back = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = back
        }
        return streak
    }

    /// Recent distinct tasks with the length you gave them, newest first.
    /// Feeds the menu bar's "Recent" submenu so a repeat is one click.
    public func recentTasks(limit: Int = 6) -> [(label: String, planned: TimeInterval)] {
        var seen = Set<String>()
        var out: [(label: String, planned: TimeInterval)] = []
        for session in sessions.reversed()
        where !session.label.isEmpty && session.label != "Untitled" {
            guard seen.insert(session.label).inserted else { continue }
            out.append((session.label, session.planned))
            if out.count >= limit { break }
        }
        return out
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        sessions = (try? decoder.decode([Session].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(sessions) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
