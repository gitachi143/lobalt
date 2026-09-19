import SwiftUI
import LobaltKit

/// What you actually spent time on, and how good your estimates were.
///
/// Lives underneath the timer in the main window rather than in a window of
/// its own — scrolling down is a cheaper way to glance at the day than
/// remembering there is a second window and going to find it.
struct HistorySection: View {
    @Environment(AppState.self) private var app
    @State private var confirmingClear = false

    private var grouped: [(day: Date, sessions: [Session])] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: app.store.recent) { calendar.startOfDay(for: $0.endedAt) }
        return buckets.keys.sorted(by: >).map { ($0, buckets[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading

            if app.store.sessions.isEmpty {
                empty
            } else {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(grouped, id: \.day) { group in
                        Section {
                            ForEach(group.sessions) { session in
                                SessionRow(session: session)
                                Rectangle()
                                    .fill(Palette.hairline)
                                    .frame(height: 1)
                                    .padding(.leading, 24)
                            }
                        } header: {
                            dayHeader(group.day, sessions: group.sessions)
                        }
                    }
                }
            }
        }
        .padding(.bottom, 28)
        .alert("Clear all history?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { app.store.clear() }
        } message: {
            Text("This removes every recorded session. It can't be undone.")
        }
    }

    private var heading: some View {
        let today = app.store.today
        let all = app.store.allTime
        return VStack(spacing: 14) {
            Rectangle().fill(Palette.hairline).frame(height: 1)

            HStack(alignment: .firstTextBaseline) {
                Text("History")
                    .font(Theme.label(13, weight: .semibold))
                    .foregroundStyle(Palette.primaryText)
                Spacer()
                if !app.store.sessions.isEmpty {
                    Button("Clear") { confirmingClear = true }
                        .buttonStyle(.plain)
                        .font(Theme.label(11))
                        .foregroundStyle(Palette.tertiaryText)
                }
            }

            HStack(spacing: 0) {
                metric("Today", "\(today.count)", TimeFormat.humane(today.totalTime))
                metric("Estimates",
                       today.hasOverrunData ? today.overrunDescription : all.overrunDescription,
                       today.hasOverrunData ? "today" : "all time")
                metric("Streak", "\(app.store.dayStreak)", app.store.dayStreak == 1 ? "day" : "days")
                metric("All time", "\(all.count)", TimeFormat.humane(all.totalTime))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func metric(_ title: String, _ value: String, _ caption: String) -> some View {
        VStack(spacing: 3) {
            Text(title.uppercased())
                .font(Theme.label(9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.tertiaryText)
            Text(value)
                .font(Theme.digits(17, weight: .semibold))
                .foregroundStyle(Palette.primaryText)
            Text(caption)
                .font(Theme.label(10))
                .foregroundStyle(Palette.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func dayHeader(_ day: Date, sessions: [Session]) -> some View {
        let stats = app.store.stats(for: sessions)
        return HStack {
            Text(dayLabel(day))
                .font(Theme.label(11, weight: .semibold))
                .foregroundStyle(Palette.secondaryText)
            Spacer()
            Text("\(sessions.count) · \(TimeFormat.humane(stats.totalTime))")
                .font(Theme.label(10))
                .foregroundStyle(Palette.tertiaryText)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 7)
        .background(Palette.canvas)
    }

    private func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "EEEEdMMM", options: 0,
                                                        locale: .current)
        return formatter.string(from: day)
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(Palette.tertiaryText)
            Text("Nothing timed yet")
                .font(Theme.label(12, weight: .medium))
                .foregroundStyle(Palette.secondaryText)
            Text("Sessions land here as soon as you start one — even the ones you think better of.")
                .font(Theme.label(11))
                .foregroundStyle(Palette.tertiaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .padding(.horizontal, 32)
    }
}

private struct SessionRow: View {
    @Environment(AppState.self) private var app
    let session: Session

    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    /// What became of it, in one word where possible.
    private var outcome: String {
        guard session.completed else { return "cancelled" }
        let delta = session.overrun
        if abs(delta) < 30 { return "finished" }
        return delta > 0 ? "+\(TimeFormat.humane(delta))" : "−\(TimeFormat.humane(-delta))"
    }

    private var outcomeColor: Color {
        guard session.completed else { return Palette.warn }
        let delta = session.overrun
        if delta > 30 { return Palette.urgent }
        return Palette.calm
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(session.completed ? Palette.calm.opacity(0.85) : Palette.warn.opacity(0.7))
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 2) {
                if editing {
                    TextField("Name this session", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .font(Theme.label(12, weight: .medium))
                        .focused($fieldFocused)
                        .onSubmit(commit)
                        // Clicking away commits. Losing a rename because you
                        // clicked the next row would be worse than the odd
                        // accidental save.
                        .onChange(of: fieldFocused) { _, focused in
                            if !focused { commit() }
                        }
                } else {
                    Text(session.label)
                        .font(Theme.label(12, weight: .medium))
                        .foregroundStyle(Palette.primaryText)
                        .lineLimit(1)
                        .onTapGesture(count: 2, perform: beginEditing)
                }
                Text(subtitle)
                    .font(Theme.label(10))
                    .foregroundStyle(Palette.tertiaryText)
            }

            Spacer(minLength: 8)

            if hovering, !editing {
                Button(action: beginEditing) { Image(systemName: "pencil") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.secondaryText)
                    .help("Rename this session")

                Button {
                    app.start(seconds: Int(session.planned), label: session.label)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.secondaryText)
                .help("Run this again")
            }

            Text(TimeFormat.humane(session.planned))
                .font(Theme.digits(11))
                .foregroundStyle(Palette.secondaryText)

            Text(outcome)
                .font(Theme.label(10, weight: .medium))
                .foregroundStyle(outcomeColor)
                .frame(width: 72, alignment: .trailing)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .background(hovering ? Color.white.opacity(0.03) : .clear)
        .contextMenu {
            Button("Rename…", action: beginEditing)
            Button("Run again") { app.start(seconds: Int(session.planned), label: session.label) }
            Button("Delete", role: .destructive) { app.store.delete(session) }
        }
    }

    /// "2:31 – 2:56 PM · ran 25 min"
    private var subtitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0,
                                                        locale: .current)
        let range = "\(formatter.string(from: session.startedAt)) – \(formatter.string(from: session.endedAt))"
        return "\(range) · ran \(TimeFormat.humane(session.actual))"
    }

    private func beginEditing() {
        draft = session.label == "Untitled" ? "" : session.label
        editing = true
        fieldFocused = true
    }

    private func commit() {
        guard editing else { return }
        editing = false
        app.store.rename(session, to: draft)
    }
}
