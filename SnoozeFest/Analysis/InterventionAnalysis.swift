import Foundation

/// All interventions that share a date, analysed together (their effects can't be separated).
struct InterventionGroup: Identifiable, Hashable {
    var date: Date
    var events: [InterventionEvent]

    var id: Date { date }
    var isOneTimeOnly: Bool { events.allSatisfy { $0.kind == .oneTime } }
    var title: String { events.map(\.title).joined(separator: " + ") }

    static func groups(from events: [InterventionEvent]) -> [InterventionGroup] {
        Dictionary(grouping: events, by: \.date)
            .map { InterventionGroup(date: $0.key, events: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.date < $1.date }
    }
}

enum Evidence {
    case strong, suggestive, none, insufficient

    /// Minimum nights on each side before we run any test.
    static let minimumNights = 5

    init(p: Double?, n: Int) {
        guard let p, n >= Evidence.minimumNights else { self = .insufficient; return }
        if p < 0.05 { self = .strong } else if p < 0.20 { self = .suggestive } else { self = .none }
    }

    var label: String {
        switch self {
        case .strong: "Strong evidence of a difference"
        case .suggestive: "Suggestive, keep watching"
        case .none: "No clear difference yet"
        case .insufficient: "Not enough data"
        }
    }

    var shortLabel: String {
        switch self {
        case .strong: "Strong"
        case .suggestive: "Suggestive"
        case .none: "Unclear"
        case .insufficient: "Not enough data"
        }
    }
}

struct WindowSummary {
    var nights: [Night]
    /// Nights whose first stretch is this many hours or less count as bad.
    var badNightThreshold: Double

    var count: Int { nights.count }
    /// Uninterrupted hours per night: the first stretch of sleep before any waking.
    var hours: [Double] { nights.map(\.uninterruptedHours) }
    var meanHours: Double { Stats.mean(hours) }
    var sdHours: Double { Stats.standardDeviation(hours) }
    var badCount: Int { nights.filter { $0.isBad(threshold: badNightThreshold) }.count }
    var badRate: Double { count == 0 ? .nan : Double(badCount) / Double(count) }
}

/// How many more nights, at the current rate, until a metric reaches strong evidence (p < 0.05).
enum SignificanceOutlook: Equatable {
    case reached
    case nights(Int)
    /// Not within `EffectAnalysis.projectionHorizon` nights (difference too small for the noise,
    /// or the before period is too short/variable to ever get there).
    case unlikely

    static let alpha = 0.05
}

struct EffectAnalysis {
    var group: InterventionGroup
    var before: WindowSummary
    var after: WindowSummary
    /// No later intervention bounds the after period, so it keeps growing as nights are logged.
    var isOngoing: Bool
    /// Included nights between the previous intervention and this one.
    var nightsSincePrevious: Int
    /// All included nights before this intervention (the before window can't be longer).
    var nightsBefore: Int
    /// The previous intervention, when the before window reaches back past it.
    var previousInBaseline: InterventionGroup?
    var hoursTest: Stats.WelchResult?
    var badNightsP: Double?
    /// Other interventions whose markers fall inside the compared span.
    var overlapping: [InterventionGroup]

    /// Longest continuation we project for (about a year).
    static let projectionHorizon = 365
    /// Minimum size of the "before" baseline.
    static let beforeNights = 7

    /// Size of the "before" window:
    /// - `beforeNights` when the previous intervention was that recent or more (the window then
    ///   reaches back past it, which the UI flags);
    /// - otherwise at least `beforeNights`, growing with the after period, but not past the
    ///   previous intervention.
    static func beforeCount(afterCount: Int, sincePrevious: Int, total: Int) -> Int {
        if sincePrevious <= beforeNights { return min(beforeNights, total) }
        return min(max(beforeNights, afterCount), sincePrevious)
    }

    /// Nights on the smaller side of the comparison.
    var n: Int { min(before.count, after.count) }
    var isOneTime: Bool { group.isOneTimeOnly }

    var hoursDifference: Double { after.meanHours - before.meanHours }
    /// Change in the share of bad nights (negative = fewer bad nights = better).
    var badNightsDifference: Double { after.badRate - before.badRate }

    var hoursEvidence: Evidence { isOneTime ? .insufficient : Evidence(p: hoursTest?.p, n: n) }
    var badNightsEvidence: Evidence { isOneTime ? .insufficient : Evidence(p: badNightsP, n: n) }

    /// Enough nights for evidence badges.
    var hasResult: Bool { !isOneTime && n >= Evidence.minimumNights }
    /// At least one night on each side, so averages (and early p-values) can be shown.
    var hasComparison: Bool { !isOneTime && n >= 1 }

    /// Largest of the two evidence levels, used for sorting/filtering history.
    var isSignificant: Bool { hoursEvidence == .strong || badNightsEvidence == .strong }

    /// Compares every included night until the next intervention (or today) with a before window
    /// sized by `beforeCount`. One-time interventions don't bound the windows.
    static func analyze(
        _ group: InterventionGroup,
        nights: [Night],
        groups: [InterventionGroup],
        badNightThreshold: Double = AppSettings.defaultBadNightThreshold
    ) -> EffectAnalysis {
        let included = nights.filter { !$0.excluded }.sorted { $0.date < $1.date }
        let allBefore = included.filter { $0.date < group.date }
        var after = included.filter { $0.date >= group.date }
        let boundaries = groups.filter { !$0.isOneTimeOnly && $0.date != group.date }

        let previous = boundaries.last { $0.date < group.date }
        let sincePrevious = previous.map { p in allBefore.filter { $0.date >= p.date }.count } ?? allBefore.count
        let next = boundaries.first { $0.date > group.date }
        if let next {
            after = after.filter { $0.date < next.date }
        }

        if group.isOneTimeOnly {
            after = after.first.map { $0.date == group.date ? [$0] : [] } ?? []
        }
        let before = Array(allBefore.suffix(beforeCount(afterCount: after.count, sincePrevious: sincePrevious,
                                                         total: allBefore.count)))
        let previousInBaseline = previous.flatMap { p in (before.first.map { $0.date < p.date } ?? false) ? p : nil }

        let spanStart = before.first?.date ?? group.date
        let spanEnd = after.last?.date ?? group.date
        let overlapping = groups.filter {
            $0.date != group.date && $0.date != previousInBaseline?.date && $0.date > spanStart && $0.date <= spanEnd
        }

        let b = WindowSummary(nights: before, badNightThreshold: badNightThreshold)
        let a = WindowSummary(nights: after, badNightThreshold: badNightThreshold)
        var hoursTest: Stats.WelchResult?
        var fisherP: Double?
        if !group.isOneTimeOnly, min(b.count, a.count) >= 1 {
            // Welch needs a variance on each side; Fisher works from a single night.
            hoursTest = Stats.welch(before: b.hours, after: a.hours)
            fisherP = Stats.fisherExact(a.badCount, a.count - a.badCount,
                                        b.badCount, b.count - b.badCount)
        }
        return EffectAnalysis(group: group, before: b, after: a, isOngoing: next == nil,
                              nightsSincePrevious: sincePrevious, nightsBefore: allBefore.count,
                              previousInBaseline: previousInBaseline,
                              hoursTest: hoursTest, badNightsP: fisherP, overlapping: overlapping)
    }

    // MARK: - Projection

    /// Before-window size once the after period has `afterCount` nights.
    private func projectedBeforeCount(_ afterCount: Int) -> Int {
        Self.beforeCount(afterCount: afterCount, sincePrevious: nightsSincePrevious, total: nightsBefore)
    }

    /// Nights after the change needed for strong evidence on uninterrupted sleep (p < 0.05 with at
    /// least `Evidence.minimumNights` on each side), if both periods keep their current mean and
    /// variance. The before window grows along with the after period, as far back as the previous
    /// change. With a single after night, its spread is assumed to match the before period's.
    /// Nil when there's nothing to project (one-time, closed period, or no nights yet).
    var hoursOutlook: SignificanceOutlook? {
        guard isOngoing, !isOneTime, after.count >= 1, before.count >= 2 else { return nil }
        let m1 = before.meanHours, v1 = Stats.variance(before.hours)
        let m2 = after.meanHours, v2 = after.count >= 2 ? Stats.variance(after.hours) : v1
        return outlook { afterCount, beforeCount in
            Stats.welch(meanBefore: m1, varianceBefore: v1, countBefore: Double(beforeCount),
                        meanAfter: m2, varianceAfter: v2, countAfter: Double(afterCount),
                        confidenceInterval: false).p
        }
    }

    /// Nights after the change needed for strong evidence on bad nights, if both periods keep
    /// their current share of bad nights.
    var badNightsOutlook: SignificanceOutlook? {
        guard isOngoing, !isOneTime, after.count >= 1, before.count >= 1 else { return nil }
        return outlook { afterCount, beforeCount in
            let bad = Int((after.badRate * Double(afterCount)).rounded())
            let beforeBad = Int((before.badRate * Double(beforeCount)).rounded())
            return Stats.fisherExact(bad, afterCount - bad, beforeBad, beforeCount - beforeBad)
        }
    }

    /// Scans future after-period sizes for the first that gives strong evidence.
    private func outlook(p: (_ afterCount: Int, _ beforeCount: Int) -> Double) -> SignificanceOutlook {
        for extra in 0...Self.projectionHorizon {
            let afterCount = after.count + extra
            let beforeCount = projectedBeforeCount(afterCount)
            guard min(afterCount, beforeCount) >= Evidence.minimumNights else { continue }
            if p(afterCount, beforeCount) < SignificanceOutlook.alpha {
                return extra == 0 ? .reached : .nights(extra)
            }
        }
        return .unlikely
    }
}
