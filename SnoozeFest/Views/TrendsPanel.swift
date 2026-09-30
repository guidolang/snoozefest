import Charts
import SwiftData
import SwiftUI

enum ChartRange: String, CaseIterable, Identifiable {
    case week = "1W", twoWeeks = "2W", threeWeeks = "3W", month = "1M", sixMonths = "6M", year = "1Y", all = "All"

    var id: String { rawValue }

    var days: Int? {
        switch self {
        case .week: 7
        case .twoWeeks: 14
        case .threeWeeks: 21
        case .month: 30
        case .sixMonths: 182
        case .year: 365
        case .all: nil
        }
    }
}

/// Everything the chart area needs for one period, computed once per render
/// (SwiftData property reads are not free).
struct TrendsData {
    var nights: [Night]
    var groups: [InterventionGroup]
    var domain: ClosedRange<Date>
    var canGoOlder: Bool
    var visibleNights: [Night]
    var visibleGroups: [InterventionGroup]
    var visibleAverage: [(date: Date, value: Double)]
    /// Unlogged mornings on screen, from the first logged night through today.
    var visibleMissing: [Date]

    /// The chart's x domain: `start` is the first morning shown, `end` the day after the last.
    /// `page` counts intervals back from the one ending today; `earliest` is the first logged date.
    static func domain(range: ChartRange, page: Int, earliest: Date) -> ClosedRange<Date> {
        if let days = range.days {
            let end = Day.adding(1 - page * days, to: Day.today)
            return Day.adding(-days, to: end)...end
        }
        return earliest...Day.adding(1, to: Day.today)
    }

    init(nights: [Night], groups: [InterventionGroup], range: ChartRange, page: Int, movingAverageNights: Int) {
        let earliest = min(nights.first?.date ?? Day.today, groups.first?.date ?? Day.today)
        let domain = Self.domain(range: range, page: page, earliest: earliest)
        let start = domain.lowerBound, end = domain.upperBound
        self.nights = nights
        self.groups = groups
        self.domain = domain
        canGoOlder = range.days != nil && start > earliest
        visibleNights = nights.filter { $0.date >= start && $0.date < end }
        visibleGroups = groups.filter { $0.date > start && $0.date <= end }
        visibleAverage = Stats.movingAverage(nights, window: movingAverageNights).filter { domain.contains($0.date) }
        let logged = Set(nights.map(\.date))
        var missing: [Date] = []
        if let first = nights.first?.date {
            var day = max(start, first)
            while day < end && day <= Day.today {
                if !logged.contains(day) { missing.append(day) }
                day = Day.adding(1, to: day)
            }
        }
        visibleMissing = missing
    }
}

/// The top of the home screen: range selector, period bar and tiles, then a white card with the
/// chart, and the interventions in the visible period. Owns its own queries and paging state, so
/// swiping between periods re-renders only these sections, not the long log list below.
/// Tapping a night selects it (the logs filter to it); tapping a marker shows the intervention.
struct TrendsSections: View {
    @Binding var selectedNight: Night?
    /// Intervals back from the one ending today (owned by the home screen, whose logs follow it).
    @Binding var page: Int
    var onOpenGroup: (InterventionGroup) -> Void

    @Query(sort: \SleepEntry.date) private var entries: [SleepEntry]
    @Query(sort: \Intervention.date) private var interventions: [Intervention]
    @AppStorage("trendsRange") private var range = ChartRange.month
    @AppStorage(AppSettings.movingAverageKey) private var movingAverageNights = AppSettings.defaultMovingAverage
    @AppStorage(AppSettings.badNightThresholdKey) private var badNightThreshold = AppSettings.defaultBadNightThreshold

    @State private var selectedGroup: InterventionGroup?
    /// Horizontal position of the chart carousel while it follows a swipe (0 = at rest).
    @State private var dragOffset: CGFloat = 0
    /// True while the carousel glides to a neighbouring period, before `page` changes.
    @State private var isSettling = false
    @State private var chartWidth: CGFloat = 0

    private func data(page: Int) -> TrendsData {
        TrendsData(nights: entries.map(\.night), groups: InterventionGroup.groups(from: interventions.map(\.event)),
                   range: range, page: page, movingAverageNights: movingAverageNights)
    }

    var body: some View {
        let data = data(page: page)
        Section {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Range", selection: $range) {
                    ForEach(ChartRange.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if data.nights.isEmpty {
                    ContentUnavailableView("No nights logged", systemImage: "chart.bar",
                                           description: Text("Nights you log will appear here."))
                } else {
                    periodBar(data)
                    summaryTiles(data)
                }
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        .listRowBackground(Color.clear)
        .onChange(of: range) {
            page = 0
            dragOffset = 0
            isSettling = false
            clearSelection()
        }

        if !data.nights.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    carousel(data)
                    legend(data)
                    selectionInfo(data)
                }
                .padding(.vertical, 6)
            }

            let analyses = data.visibleGroups.map {
                EffectAnalysis.analyze($0, nights: data.nights, groups: data.groups, badNightThreshold: badNightThreshold)
            }
            PeriodInterventionsSection(analyses: analyses, onOpen: onOpenGroup)
        }
    }

    // MARK: - Paging

    /// Writes only when something is selected: `selectedNight` belongs to the home screen, and any
    /// write re-renders the whole log list.
    private func clearSelection() {
        if selectedGroup != nil { selectedGroup = nil }
        if selectedNight != nil { selectedNight = nil }
    }

    // MARK: - Carousel

    /// The chart with its neighbouring periods on either side (older on the left). The strip
    /// follows the finger and glides into place; `page` (and with it the tiles, interventions and
    /// logs) only changes once the glide has finished, so the animation itself stays light.
    /// Neighbours are only drawn while swiping or gliding.
    private func carousel(_ data: TrendsData) -> some View {
        let yMax = max(12, (data.nights.map(\.totalHours).max() ?? 0).rounded(.up))
        let showNeighbours = dragOffset != 0 || isSettling
        return GeometryReader { geo in
            let width = geo.size.width
            HStack(spacing: 0) {
                neighbour(page + 1, show: showNeighbours && data.canGoOlder, yMax: yMax)
                    .frame(width: width)
                chart(data, yMax: yMax, selectedGroup: $selectedGroup, selectedNight: $selectedNight)
                    .frame(width: width)
                neighbour(page - 1, show: showNeighbours && page > 0, yMax: yMax)
                    .frame(width: width)
            }
            .offset(x: -width + dragOffset)
            .onAppear { chartWidth = width }
            .onChange(of: width) { chartWidth = width }
        }
        .frame(height: 296)
        .clipped()
        .contentShape(Rectangle())
        .simultaneousGesture(swipe(data))
    }

    @ViewBuilder private func neighbour(_ page: Int, show: Bool, yMax: Double) -> some View {
        if show {
            chart(data(page: page), yMax: yMax, selectedGroup: .constant(nil), selectedNight: .constant(nil))
                .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }

    private func chart(_ data: TrendsData, yMax: Double,
                       selectedGroup: Binding<InterventionGroup?>, selectedNight: Binding<Night?>) -> some View {
        SleepChart(
            nights: data.visibleNights,
            average: data.visibleAverage,
            missing: data.visibleMissing,
            groups: data.visibleGroups,
            domain: data.domain,
            yMax: yMax,
            selectedGroup: selectedGroup,
            selectedNight: selectedNight
        )
        .padding(.top, 16)  // room for the axis label and flags above the plot
    }

    private func goOlder() { slide(by: 1) }
    private func goNewer() { slide(by: -1) }

    /// Glides one period (1 = older, -1 = newer), then switches `page` without animation.
    private func slide(by step: Int) {
        guard !isSettling, chartWidth > 0 else { return }
        isSettling = true
        withAnimation(.snappy(duration: 0.32)) {
            dragOffset = step > 0 ? chartWidth : -chartWidth
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                page += step
                dragOffset = 0
                isSettling = false
            }
            clearSelection()
        }
    }

    /// Horizontal swipe on the chart: the chart follows the finger (with resistance where there's
    /// no neighbouring period) and pages when released far or fast enough.
    private func swipe(_ data: TrendsData) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard range.days != nil, !isSettling else { return }
                let dx = value.translation.width
                // Leave mostly-vertical drags to the list's scrolling.
                if dragOffset == 0 && abs(dx) < abs(value.translation.height) { return }
                let allowed = (dx > 0 && data.canGoOlder) || (dx < 0 && page > 0)
                dragOffset = allowed ? dx : dx * 0.25
            }
            .onEnded { value in
                guard range.days != nil, !isSettling, dragOffset != 0 else { return }
                let projected = value.predictedEndTranslation.width
                let threshold = chartWidth * 0.3
                if projected > threshold, data.canGoOlder {
                    slide(by: 1)
                } else if projected < -threshold, page > 0 {
                    slide(by: -1)
                } else {
                    withAnimation(.snappy) { dragOffset = 0 }
                }
            }
    }

    /// Dates on screen, with arrows to page by interval ("All" has nothing to page).
    /// Fixed height so paging never shifts the chart.
    private func periodBar(_ data: TrendsData) -> some View {
        let first = data.domain.lowerBound
        let last = Day.adding(-1, to: data.domain.upperBound)
        let style = Date.FormatStyle().month(.abbreviated).day()
        let sameYear = Day.calendar.isDate(first, equalTo: last, toGranularity: .year)
        let paged = range.days != nil
        return HStack {
            Button(action: goOlder) { Image(systemName: "chevron.left") }
                .disabled(!data.canGoOlder)
                .opacity(paged ? 1 : 0)
                .accessibilityLabel("Earlier")
            Spacer()
            VStack(spacing: 0) {
                Text("\(first.formatted(sameYear ? style : style.year())) – \(last.formatted(style.year()))")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                Button("Back to today") {
                    page = 0
                    clearSelection()
                }
                .font(.caption)
                .opacity(page > 0 ? 1 : 0)
                .disabled(page == 0)
            }
            Spacer()
            Button(action: goNewer) { Image(systemName: "chevron.right") }
                .disabled(page == 0)
                .opacity(paged ? 1 : 0)
                .accessibilityLabel("Later")
        }
        .buttonStyle(.borderless)
        .font(.title3)
    }

    // MARK: - Pieces

    private func summaryTiles(_ data: TrendsData) -> some View {
        let included = data.visibleNights.filter { !$0.excluded }
        let avg = Stats.mean(included.map(\.uninterruptedHours))
        let badCount = included.filter { $0.isBad(threshold: badNightThreshold) }.count
        let bad = included.isEmpty ? Double.nan : Double(badCount) / Double(included.count)
        return HStack {
            StatTile(title: "Uninterrupted", value: avg.isNaN ? "–" : "\(avg.formatted(.number.precision(.fractionLength(1)))) h",
                     caption: "avg first stretch")
            StatTile(title: "Bad nights", value: included.isEmpty ? "–" : "\(bad.percentText) (\(badCount))", caption: "woke or ≤ \(badNightThreshold.hoursText) h")
        }
    }

    private func legend(_ data: TrendsData) -> some View {
        let sleep = LegendItem(color: Theme.firstStretch, label: "Sleep")
        let woke = LegendItem(color: Theme.laterStretch, label: "After waking")
        let avg = LegendItem(color: Theme.average, label: "\(movingAverageNights)-night avg", line: true)
            .accessibilityLabel("\(movingAverageNights)-night average of uninterrupted sleep")
        let intervention = LegendItem(color: Theme.intervention, label: "Intervention", line: true, vertical: true)
        let missing = LegendItem(color: Theme.attention.opacity(0.25), label: "Missing")
        let showMissing = !data.visibleMissing.isEmpty
        // One row when it fits, otherwise two.
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                sleep; woke; avg; intervention
                if showMissing { missing }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) { sleep; woke; avg }
                HStack(spacing: 12) {
                    intervention
                    if showMissing { missing }
                }
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private func selectionInfo(_ data: TrendsData) -> some View {
        if let group = selectedGroup {
            let analysis = EffectAnalysis.analyze(group, nights: data.nights, groups: data.groups,
                                                  badNightThreshold: badNightThreshold)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(group.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { selectedGroup = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Close")
                }
                ForEach(group.events) { InterventionRow(event: $0) }
                if analysis.hasComparison {
                    HStack {
                        StatTile(title: "Uninterrupted sleep", value: analysis.hoursDifference.signedHoursText,
                                 caption: analysis.hoursEvidence.shortLabel)
                        StatTile(title: "Bad nights", value: analysis.badNightsDifference.signedPointsText,
                                 caption: analysis.badNightsEvidence.shortLabel)
                    }
                }
                Button { onOpenGroup(group) } label: {
                    Label("See before vs. after", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
            .padding()
            .background(Theme.intervention.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.intervention.opacity(0.3)))
        } else if let night = selectedNight {
            HStack {
                Label("Showing \(night.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) in the logs below",
                      systemImage: "arrow.down.circle")
                Spacer()
                Button("Clear") { selectedNight = nil }
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .padding(.trailing, 4)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

/// "Interventions in this period": each intervention's before/after result, most recent first;
/// tapping one opens its details.
struct PeriodInterventionsSection: View {
    var analyses: [EffectAnalysis]
    var onOpen: (InterventionGroup) -> Void

    var body: some View {
        Section {
            if analyses.isEmpty {
                EmptySectionNote(text: "No interventions in this period", systemImage: "flag.slash")
            }
            ForEach(analyses.sorted { $0.group.date > $1.group.date }, id: \.group.date) { analysis in
                Button { onOpen(analysis.group) } label: {
                    HStack {
                        HistoryRow(analysis: analysis)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            SectionTitle("Interventions in this period")
        }
    }
}

/// A prominent section heading, with optional trailing controls.
struct SectionTitle<Trailing: View>: View {
    var title: String
    var trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title3.weight(.bold)).foregroundStyle(Color.primary)  // a concrete color: list headers dim hierarchical styles
            Spacer()
            trailing
        }
        .textCase(nil)
        .padding(.top, 8)
    }
}

/// A small pennant with its pole on the left edge, drawn as a native chart symbol.
struct FlagSymbol: ChartSymbolShape {
    var perceptualUnitRect: CGRect { CGRect(x: 0, y: 0, width: 1, height: 1) }

    func path(in rect: CGRect) -> Path {
        let pole = max(1.2, rect.width * 0.14)
        var path = Path(CGRect(x: rect.minX, y: rect.minY, width: pole, height: rect.height))
        path.move(to: CGPoint(x: rect.minX + pole, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.3))
        path.addLine(to: CGPoint(x: rect.minX + pole, y: rect.minY + rect.height * 0.62))
        path.closeSubpath()
        return path
    }
}

/// Muted icon + text shown in place of an empty list section.
struct EmptySectionNote: View {
    var text: String
    var systemImage: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
    }
}

private struct LegendItem: View {
    var color: Color
    var label: String
    var line = false
    var vertical = false

    var body: some View {
        HStack(spacing: 4) {
            if line {
                RoundedRectangle(cornerRadius: 1).fill(color)
                    .frame(width: vertical ? 2 : 12, height: vertical ? 12 : 2)
            } else {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            }
            Text(label).lineLimit(1).fixedSize()
        }
    }
}

/// Nightly stacked columns + moving average + intervention markers.
struct SleepChart: View {
    var nights: [Night]
    var average: [(date: Date, value: Double)]
    /// Unlogged mornings, shown as a light orange background column (no data, so no bar).
    var missing: [Date] = []
    var groups: [InterventionGroup]
    var domain: ClosedRange<Date>
    /// Top of the hours axis; shared by every period so paging doesn't rescale the chart.
    var yMax: Double
    @Binding var selectedGroup: InterventionGroup?
    @Binding var selectedNight: Night?

    private struct Stretch: Identifiable {
        var id: String
        var date: Date
        var hours: Double
        var kind: String
    }

    private var stretches: [Stretch] {
        nights.flatMap { night in
            night.segments.enumerated().map { index, hours in
                Stretch(id: "\(night.date.timeIntervalSince1970)-\(index)", date: night.date, hours: hours,
                        kind: night.excluded ? "Excluded" : (index == 0 ? "Sleep" : "After waking"))
            }
        }
    }

    /// Long ranges: gap-free columns and lighter markers so the chart stays readable.
    private var dense: Bool { Day.between(domain.lowerBound, domain.upperBound) > 60 }


    var body: some View {
        Chart {
            ForEach(missing, id: \.self) { day in
                let faded = selectedNight != nil && selectedNight?.date != day
                BarMark(x: .value("Night", day, unit: .day), yStart: .value("Hours", 0), yEnd: .value("Hours", yMax),
                        width: dense ? .ratio(1) : .automatic)
                    .foregroundStyle(Theme.attention.opacity(faded ? 0.06 : 0.18))
                    .accessibilityLabel("No data for \(day.formatted(date: .abbreviated, time: .omitted))")
            }
            ForEach(stretches) { stretch in
                BarMark(
                    x: .value("Night", stretch.date, unit: .day),
                    y: .value("Hours", stretch.hours),
                    width: dense ? .ratio(1) : .automatic
                )
                .foregroundStyle(by: .value("Type", stretch.kind))
                .opacity(selectedNight == nil || selectedNight?.date == stretch.date ? 1 : 0.35)
            }
            ForEach(average, id: \.date) { point in
                LineMark(
                    x: .value("Night", point.date, unit: .day),
                    y: .value("Average", point.value),
                    series: .value("Series", "average")
                )
                .foregroundStyle(Theme.average)
                .lineStyle(StrokeStyle(lineWidth: dense ? 1.5 : 2))
                .interpolationMethod(.monotone)
            }
            ForEach(groups) { group in
                let selected = selectedGroup?.date == group.date
                let flag: CGFloat = selected ? 13 : (dense ? 7 : 10)
                RuleMark(x: .value("Intervention", group.date))
                    .foregroundStyle(Theme.intervention.opacity(selectedGroup == nil || selected ? 1 : 0.4))
                    .lineStyle(StrokeStyle(lineWidth: selected ? 3 : (dense ? 0.75 : 1.5), dash: group.isOneTimeOnly ? [3, 3] : []))
                    .accessibilityLabel(group.title)
                // A chart symbol rather than an annotation view: annotations are SwiftUI views
                // per mark and made paging between periods stutter.
                PointMark(x: .value("Intervention", group.date), y: .value("Hours", yMax))
                    .symbol(FlagSymbol())
                    .symbolSize(flag * flag)
                    .foregroundStyle(Theme.intervention)
                    .offset(x: flag / 2, y: -flag / 2 - 2)
                    .accessibilityHidden(true)
            }
        }
        .chartForegroundStyleScale([
            "Sleep": Theme.firstStretch,
            "After waking": Theme.laterStretch,
            "Excluded": Theme.excluded,
        ])
        .chartLegend(.hidden)
        .chartXScale(domain: domain)
        .chartYScale(domain: 0...yMax)
        // Date labels only: no vertical gridlines or ticks.
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel() }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: 2)) { value in
                AxisGridLine()
                AxisValueLabel { if let h = value.as(Double.self) { Text("\(Int(h))h") } }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        handleTap(at: tap.location, proxy: proxy, geo: geo)
                    })
            }
        }
    }

    private func handleTap(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geo[plotFrame].origin
        let x = location.x - origin.x

        // Prefer the nearest intervention marker within a finger's width.
        let nearest = groups
            .compactMap { group in proxy.position(forX: group.date).map { (group, abs($0 - x)) } }
            .min { $0.1 < $1.1 }
        if let (group, distance) = nearest, distance < 22 {
            selectedNight = nil
            selectedGroup = selectedGroup?.date == group.date ? nil : group
            return
        }
        if let date: Date = proxy.value(atX: x) {
            let day = Day.start(date)
            selectedGroup = nil
            // A missing night selects an empty placeholder, so the logs show its "Log it now" row.
            let night = nights.first { $0.date == day } ?? (missing.contains(day) ? Night(date: day, segments: []) : nil)
            selectedNight = selectedNight?.date == day ? nil : night
        }
    }
}
