import SwiftUI
import LobaltKit

/// What you actually spent time on, and how good your estimates were.
struct HistoryView: View {
    @Environment(AppState.self) private var app
    @State private var confirmingClear = false

    private var grouped: [(day: Date, sessions: [Session])] {
        let cal = Calendar.current
        let buckets = Dictionary(grouping: app.store.recent) { cal.startOfDay(for: $0.endedAt) }
        return buckets.keys.sorted(by: >).map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        VStack(spacing: 0) {
            summary
            Divider()

            if app.store.sessions.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(grouped, id: \.day) { group in
                            Section {
                                ForEach(group.sessions) { session in
                                    SessionRow(session: session)
                                    Divider().padding(.leading, 16)
                                }
                            } header: {
                                dayHeader(group.day, sessions: group.sessions)
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 380)
        .navigationTitle("History")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) { confirmingClear = true } label: {
                    Label("Clear", systemImage: "trash")
                }
                .disabled(app.store.sessions.isEmpty)
            }
        }
        .alert("Clear all history?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { app.store.clear() }
        } message: {
            Text("This removes every recorded session. It can't be undone.")
        }
    }

    private var summary: some View {
        let today = app.store.today
        let all = app.store.allTime
        return HStack(spacing: 0) {
            metric("Today", "\(today.count)", TimeFormat.humane(today.totalTime))
            metric("Estimates", today.hasOverrunData ? today.overrunDescription : all.overrunDescription,
                   today.hasOverrunData ? "today" : "all time")
            metric("Streak", "\(app.store.dayStreak)", app.store.dayStreak == 1 ? "day" : "days")
            metric("All time", "\(all.count)", TimeFormat.humane(all.totalTime))
        }
        .padding(.vertical, 14)
    }

    private func metric(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(spacing: 3) {
            Text(title.uppercased())
                .font(Theme.label(9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(Theme.digits(19, weight: .semibold))
                .foregroundStyle(.primary)
            Text(caption)
                .font(Theme.label(10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func dayHeader(_ day: Date, sessions: [Session]) -> some View {
        let stats = app.store.stats(for: sessions)
        return HStack {
            Text(dayLabel(day))
                .font(Theme.label(11, weight: .semibold))
            Spacer()
            Text("\(sessions.count) · \(TimeFormat.humane(stats.totalTime))")
                .font(Theme.label(10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEEEdMMM", options: 0, locale: .current)
        return f.string(from: day)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No sessions yet")
                .font(Theme.label(13, weight: .medium))
            Text("Timers you run for at least twenty seconds show up here.")
                .font(Theme.label(11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SessionRow: View {
    @Environment(AppState.self) private var app
    let session: Session
    @State private var hovering = false

    private var overColor: Color {
        if !session.completed { return .secondary }
        if session.overrun > 30 { return Palette.urgent }
        if session.overrun < -30 { return Palette.calm }
        return .secondary
    }

    private var overText: String {
        guard session.completed else { return "stopped early" }
        let delta = session.overrun
        if abs(delta) < 30 { return "on time" }
        return delta > 0 ? "+\(TimeFormat.humane(delta))" : "−\(TimeFormat.humane(-delta))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(session.completed ? Palette.calm.opacity(0.8) : Color.secondary.opacity(0.4))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.label)
                    .font(Theme.label(12, weight: .medium))
                    .lineLimit(1)
                Text(timeRange)
                    .font(Theme.label(10))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 8)

            Text(TimeFormat.humane(session.planned))
                .font(Theme.digits(11))
                .foregroundStyle(.secondary)

            Text(overText)
                .font(Theme.label(10, weight: .medium))
                .foregroundStyle(overColor)
                .frame(width: 78, alignment: .trailing)

            if hovering {
                Button {
                    app.start(seconds: Int(session.planned), label: session.label)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .help("Run this again")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Run again") { app.start(seconds: Int(session.planned), label: session.label) }
            Button("Delete", role: .destructive) { app.store.delete(session) }
        }
    }

    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: .current)
        return "\(f.string(from: session.startedAt)) – \(f.string(from: session.endedAt))"
    }
}
