import SwiftData
import SwiftUI

enum HomeSheet: Identifiable {
    /// Log or edit one specific night.
    case night(Date)
    case intervention(Intervention?)

    var id: String {
        switch self {
        case .night(let date): "night-\(date.timeIntervalSince1970)"
        case .intervention(let i): "intervention-\(i?.id.uuidString ?? "new")"
        }
    }
}

enum NightFilter: String, CaseIterable, Identifiable {
    case all = "All nights"
    case good = "Good nights"
    case bad = "Bad nights"
    case excluded = "Excluded nights"
    case notes = "Nights with notes"
    case missing = "Missing nights"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .all: "list.bullet"
        case .good: "checkmark.circle"
        case .bad: "exclamationmark.triangle"
        case .excluded: "eye.slash"
        case .notes: "note.text"
        case .missing: "questionmark.circle"
        }
    }

    /// Whether a logged night is shown (missing nights are rows of their own).
    func matches(_ night: Night, badNightThreshold: Double) -> Bool {
        switch self {
        case .all: true
        case .good: !night.isBad(threshold: badNightThreshold)
        case .bad: night.isBad(threshold: badNightThreshold)
        case .excluded: night.excluded
        case .notes: !night.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .missing: false
        }
    }
}

/// The app's single screen: chart and intervention results on top, the night-by-night log below.
struct HomeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SleepEntry.date, order: .reverse) private var entries: [SleepEntry]
    @Query(sort: \Intervention.date, order: .reverse) private var interventions: [Intervention]
    @AppStorage(AppSettings.badNightThresholdKey) private var badNightThreshold = AppSettings.defaultBadNightThreshold
    @AppStorage("trendsRange") private var range = ChartRange.month

    @State private var sheet: HomeSheet?
    @State private var filter = NightFilter.all
    @State private var showSettings = false
    /// Bumped when a save turns a night good, to play the confetti.
    @State private var celebrations = 0
    /// Refreshed at midnight so the "Log last night" button appears without relaunching.
    @State private var today = Day.today

    /// A night tapped in the chart; the logs filter to its date.
    @State private var selectedNight: Night?
    @State private var detailGroup: InterventionGroup?
    /// The chart's period (intervals back from today); the logs show the same dates.
    @State private var page = 0

    var body: some View {
        let entryByDate = entryByDate
        let logs = logRows(entryByDate: entryByDate).within(visibleDomain)
        let sections = monthSections(entryDates: logs.days, interventionDates: logs.interventions.keys)

        NavigationStack {
            List {
                if entryByDate[today] == nil {
                    Section { logLastNightButton }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                TrendsSections(selectedNight: $selectedNight, page: $page, onOpenGroup: { detailGroup = $0 })

                logsHeader(count: logs.nightCount, isEmpty: sections.isEmpty && !(entries.isEmpty && interventions.isEmpty))

                if entries.isEmpty && interventions.isEmpty {
                    Section {
                        Text("Log each morning how your child slept last night, and record any interventions you try (a new supplement, routine or medication). After a couple of weeks, the chart and results above will show whether an intervention made a difference.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }

                ForEach(sections, id: \.month) { section in
                    Section(section.month.formatted(.dateTime.month(.wide).year())) {
                        ForEach(section.days, id: \.self) { day in
                            if logs.missing.contains(day) {
                                Button { sheet = .night(day) } label: { MissingNightRow(date: day) }
                                    .buttonStyle(.plain)
                            }
                            if let entry = logs.entries[day] {
                                let isBad = entry.night.isBad(threshold: badNightThreshold)
                                Button { sheet = .night(day) } label: { NightRow(entry: entry, isBad: isBad) }
                                    .buttonStyle(.plain)
                                    .listRowBackground(isBad && !entry.excludeFromAnalysis ? Theme.badNight.opacity(0.08) : nil)
                                    .swipeActions {
                                        Button(role: .destructive) { delete(entry) } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                            }
                            ForEach(logs.interventions[day] ?? []) { intervention in
                                Button { sheet = .intervention(intervention) } label: {
                                    InterventionRow(event: intervention.event)
                                }
                                .buttonStyle(.plain)
                                .swipeActions {
                                    Button(role: .destructive) { delete(intervention) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .listSectionSpacing(.compact)
            .navigationBarTitleDisplayMode(.inline)
            .contentMargins(.top, 4, for: .scrollContent)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .intervention(nil) } label: {
                        Label("Log intervention", systemImage: "flag")
                    }
                }
            }
            .navigationDestination(item: $detailGroup) { InterventionDetailView(group: $0) }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
                today = Day.today
            }
            .onChange(of: scenePhase) {
                if scenePhase == .active { today = Day.today }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .night(let date): LogNightView(date: date, onSave: celebrate)
                case .intervention(let existing): InterventionSheet(existing: existing)
                }
            }
            .overlay { ConfettiView(trigger: celebrations) }
            .sensoryFeedback(.success, trigger: celebrations)
        }
    }

    private func celebrate(_ becameGood: Bool) {
        if becameGood { celebrations += 1 }
    }

    // MARK: - Pieces

    private var logLastNightButton: some View {
        Button { sheet = .night(today) } label: {
            // Icon + text rather than a Label, which the glass style renders with a faint icon.
            HStack(spacing: 6) {
                Image(systemName: "plus").fontWeight(.bold)
                Text("Log last night")
            }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .modifier(ProminentCapsuleStyle())
        .controlSize(.large)
        .tint(Theme.attention)
        .accessibilityHint("Night of \(Day.nightLabel(forMorning: today))")
    }

    /// "Logs" heading with the filter menu; while a filter is on, a row says how many nights match.
    /// (A night picked in the chart just narrows the list; the chart has its own "Clear".)
    private func logsHeader(count: Int, isEmpty: Bool) -> some View {
        Section {
            if isEmpty {
                EmptySectionNote(text: filter == .all ? "No logs in this period" : "No \(filter.rawValue.lowercased()) in this period",
                                 systemImage: filter == .all ? "moon.zzz" : filter.symbol)
            }
            if filter != .all && selectedNight == nil && !isEmpty {
                HStack {
                    Label("\(count) \(filter.rawValue.lowercased())", systemImage: filter.symbol)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Show all") { withAnimation { filter = .all } }
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                }
            }
        } header: {
            SectionTitle("Logs") {
                Menu {
                    Picker("Show", selection: $filter.animation()) {
                        ForEach(NightFilter.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
                    }
                } label: {
                    Image(systemName: filter == .all
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Filter logs")
            }
        }
    }

    // MARK: - Log rows

    private struct LogRows {
        var entries: [Date: SleepEntry]
        var missing: Set<Date>
        var interventions: [Date: [Intervention]]
        var days: [Date] { Array(entries.keys) + Array(missing) }
        var nightCount: Int { entries.count + missing.count }

        /// Only the dates in the chart's current period.
        func within(_ domain: ClosedRange<Date>) -> LogRows {
            LogRows(entries: entries.filter { $0.key >= domain.lowerBound && $0.key < domain.upperBound },
                    missing: missing.filter { $0 >= domain.lowerBound && $0 < domain.upperBound },
                    interventions: interventions.filter { domain.contains($0.key) })
        }
    }

    /// The chart's current period (same as `TrendsData.domain`).
    private var visibleDomain: ClosedRange<Date> {
        let earliest = min(entries.last?.date ?? Day.today, interventions.last?.date ?? Day.today)
        return TrendsData.domain(range: range, page: page, earliest: earliest)
    }

    /// What the log list shows: a night picked in the chart overrides the filter.
    private func logRows(entryByDate: [Date: SleepEntry]) -> LogRows {
        if let night = selectedNight {
            let day = night.date
            return LogRows(entries: entryByDate.filter { $0.key == day },
                           missing: entryByDate[day] == nil ? [day] : [],
                           interventions: interventionsByDate.filter { $0.key == day })
        }
        switch filter {
        case .all:
            return LogRows(entries: entryByDate, missing: missingMornings(recorded: entryByDate, includingToday: false),
                           interventions: interventionsByDate)
        case .missing:
            return LogRows(entries: [:], missing: missingMornings(recorded: entryByDate, includingToday: true),
                           interventions: [:])
        default:
            return LogRows(entries: entryByDate.filter { filter.matches($0.value.night, badNightThreshold: badNightThreshold) },
                           missing: [], interventions: [:])
        }
    }

    /// Unlogged mornings since the first logged night. Last night is left out of the full list
    /// because the "Log last night" button covers it.
    private func missingMornings(recorded: [Date: SleepEntry], includingToday: Bool) -> Set<Date> {
        guard let first = entries.last?.date else { return [] }
        var missing = Set<Date>()
        var day = Day.adding(1, to: first)
        while day < today || (includingToday && day == today) {
            if recorded[day] == nil { missing.insert(day) }
            day = Day.adding(1, to: day)
        }
        return missing
    }

    // MARK: - Timeline grouping

    private var entryByDate: [Date: SleepEntry] {
        Dictionary(entries.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var interventionsByDate: [Date: [Intervention]] {
        Dictionary(grouping: interventions, by: \.date)
    }

    private func monthSections(entryDates: some Sequence<Date>, interventionDates: some Sequence<Date>) -> [(month: Date, days: [Date])] {
        let days = Set(entryDates).union(interventionDates).sorted(by: >)
        let grouped = Dictionary(grouping: days) {
            Day.calendar.dateInterval(of: .month, for: $0)?.start ?? $0
        }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    private func delete(_ model: some PersistentModel) {
        context.delete(model)
        try? context.save()
    }
}

/// Placeholder for an unlogged morning between logged nights.
struct MissingNightRow: View {
    var date: Date

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(date.formatted(.dateTime.day())).font(.headline).monospacedDigit().foregroundStyle(.secondary)
                Text(date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 34)
            Text("No data.").font(.subheadline).foregroundStyle(.secondary)
            Text("Log it now").font(.subheadline.weight(.semibold)).foregroundStyle(.tint)
            Spacer()
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("No data for the night of \(Day.nightLabel(forMorning: date))")
        .accessibilityHint("Log it now")
    }
}

struct NightRow: View {
    var entry: SleepEntry
    var isBad = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.date.formatted(.dateTime.day())).font(.headline).monospacedDigit()
                    .foregroundStyle(isBad ? Theme.badNight : .primary)
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.segments.map(\.hoursText).joined(separator: " + "))
                        .font(.subheadline.weight(.medium)).monospacedDigit()
                    if isBad {
                        Text(entry.isInterrupted ? "Woke \(entry.wakeCount)×" : "Short")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.badNight)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.badNight.opacity(0.15), in: Capsule())
                    }
                    if entry.excludeFromAnalysis {
                        Image(systemName: "eye.slash").font(.caption).foregroundStyle(.secondary)
                            .accessibilityLabel("Excluded from analysis")
                    }
                    Spacer()
                    Text("\(entry.totalHours.hoursText) h").font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                NightBar(segments: entry.segments, excluded: entry.excludeFromAnalysis)
                if !entry.note.isEmpty {
                    Text(entry.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

struct InterventionRow: View {
    var event: InterventionEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: event.kind.symbol).foregroundStyle(Theme.intervention)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(event.kind.label) \(event.name)").font(.subheadline.weight(.semibold))
                if !event.details.isEmpty {
                    Text(event.details).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
