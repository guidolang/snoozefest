import Foundation
import Testing
@testable import SnoozeFest

/// Reference values computed with scipy 1.18 (`ttest_ind(after, before, equal_var=False)`, `fisher_exact`).
struct StatisticsTests {
    @Test func welchEqualVariances() throws {
        let r = try #require(Stats.welch(before: [8, 9, 10, 7, 9], after: [10, 11, 9, 10, 12]))
        #expect(abs(r.t - 2.496150883013532) < 1e-9)
        #expect(abs(r.p - 0.037164277872899484) < 1e-9)
        #expect(abs(r.degreesOfFreedom - 8.0) < 1e-9)
        #expect(abs(r.ciLow - 0.13711676981787813) < 1e-6)
        #expect(abs(r.ciHigh - 3.4628832301821233) < 1e-6)
        #expect(abs(r.difference - 1.8) < 1e-9)
    }

    @Test func welchUnequalVariances() throws {
        let r = try #require(Stats.welch(before: [5, 9, 10, 8, 4, 10, 9.5], after: [9, 9.5, 10, 9, 8.5, 9.25]))
        #expect(abs(r.t - 1.344774730553782) < 1e-9)
        #expect(abs(r.p - 0.22307696542438007) < 1e-9)
        #expect(abs(r.degreesOfFreedom - 6.599180970554379) < 1e-9)
        #expect(abs(r.ciLow - -0.9985510468728123) < 1e-6)
        #expect(abs(r.ciHigh - 3.5580748563966225) < 1e-6)
    }

    @Test func welchEdgeCases() throws {
        #expect(Stats.welch(before: [9], after: [9, 10]) == nil)
        let same = try #require(Stats.welch(before: [9, 9, 9], after: [9, 9, 9]))
        #expect(same.p == 1)
        let shifted = try #require(Stats.welch(before: [9, 9, 9], after: [10, 10, 10]))
        #expect(shifted.p == 0)
        let identical = try #require(Stats.welch(before: [8, 9, 10], after: [8, 9, 10]))
        #expect(abs(identical.p - 1) < 1e-12)
    }

    @Test func tQuantile() {
        #expect(abs(Stats.studentTQuantile(p: 0.975, df: 7.3) - 2.345066736547703) < 1e-6)
    }

    @Test(arguments: [
        ((3, 11, 9, 5), 0.05423789653161037),
        ((0, 5, 5, 0), 0.007936507936507938),
        ((12, 2, 9, 5), 0.38454106280193234),
        ((7, 7, 7, 7), 1.0),
    ])
    func fisher(table: (Int, Int, Int, Int), expected: Double) {
        #expect(abs(Stats.fisherExact(table.0, table.1, table.2, table.3) - expected) < 1e-9)
    }

    @Test func movingAverageUsesCalendarWindow() {
        let d0 = Day.start(Date(timeIntervalSince1970: 1_750_000_000))
        let nights = [
            Night(date: d0, segments: [8]),
            Night(date: Day.adding(1, to: d0), segments: [10]),
            Night(date: Day.adding(2, to: d0), segments: [5], excluded: true),
            Night(date: Day.adding(3, to: d0), segments: [6]),
        ]
        let avg = Stats.movingAverage(nights, window: 3)
        #expect(avg.map(\.value) == [8, 9, 8])  // day 3 window = days 1...3 → (10 + 6) / 2
    }

    @Test func movingAverageUsesFirstStretch() {
        let d0 = Day.start(Date(timeIntervalSince1970: 1_750_000_000))
        let nights = [Night(date: d0, segments: [4, 5]), Night(date: Day.adding(1, to: d0), segments: [8])]
        #expect(Stats.movingAverage(nights, window: 7).map(\.value) == [4, 6])
    }
}

struct InterventionAnalysisTests {
    let start = Day.start(Date(timeIntervalSince1970: 1_750_000_000))

    func night(_ offset: Int, _ segments: [Double], excluded: Bool = false) -> Night {
        Night(date: Day.adding(offset, to: start), segments: segments, excluded: excluded)
    }

    func started(_ offset: Int, _ name: String = "X") -> InterventionGroup {
        let date = Day.adding(offset, to: start)
        return InterventionGroup(date: date, events: [InterventionEvent(date: date, name: name, kind: .started)])
    }

    @Test func usesWeekBeforeAndAllNightsAfter() {
        // 10 nights before (interrupted), 6 after (solid 10h): the last 7 before vs. all 6 after.
        let before = (0..<10).map { night($0, [5, 3]) }
        let after = (10..<16).map { night($0, [10]) }
        let group = started(10)
        let a = EffectAnalysis.analyze(group, nights: before + after, groups: [group])
        #expect(a.before.count == 7)
        #expect(a.after.count == 6)
        #expect(a.n == 6)
        #expect(a.before.nights.first?.date == Day.adding(3, to: start))
        #expect(a.isOngoing)
        #expect(a.hoursDifference == 5)  // uninterrupted hours: first stretch 5h → 10h
        #expect(a.badNightsDifference == -1)  // every night bad → none bad
        #expect(a.badNightsEvidence == .strong)
        #expect(a.hoursOutlook == .reached)
        #expect(a.badNightsOutlook == .reached)
    }

    @Test func beforeWindowGrowsWithAfterNights() {
        let group = started(20)
        let nights = (0..<45).map { night($0, [9]) }
        // 12 after nights → 12 before; 25 after → capped at the 20 available before.
        #expect(EffectAnalysis.analyze(group, nights: Array(nights.prefix(32)), groups: [group]).before.count == 12)
        #expect(EffectAnalysis.analyze(group, nights: nights, groups: [group]).before.count == 20)
        // Few after nights still get a full week of baseline.
        #expect(EffectAnalysis.analyze(group, nights: Array(nights.prefix(23)), groups: [group]).before.count == 7)
        // A one-time event is compared against the week before it.
        let oneTime = InterventionGroup(date: group.date, events: [InterventionEvent(date: group.date, name: "Y", kind: .oneTime)])
        #expect(EffectAnalysis.analyze(oneTime, nights: nights, groups: [oneTime]).before.count == 7)
    }

    @Test func beforeWindowStopsAtPreviousInterventionWhenLongerThanAWeek() {
        let g1 = started(0, "A"), g2 = started(12, "B")
        let nights = (0..<40).map { night($0, [9]) }
        // 12 nights since A: before grows with the after period but stops at A.
        let b = EffectAnalysis.analyze(g2, nights: nights, groups: [g1, g2])
        #expect(b.after.count == 28)
        #expect(b.before.count == 12)
        #expect(b.previousInBaseline == nil)
        // Few after nights still get a week.
        #expect(EffectAnalysis.analyze(g2, nights: Array(nights.prefix(15)), groups: [g1, g2]).before.count == 7)
    }

    @Test func badNightDefinition() {
        #expect(night(0, [6]).isBad(threshold: 6))
        #expect(!night(0, [6.25]).isBad(threshold: 6))
        #expect(night(0, [9, 1]).isBad(threshold: 6))  // any waking
        #expect(!night(0, [7]).isBad(threshold: 6))
        #expect(night(0, [7]).isBad(threshold: 7))
    }

    @Test func thresholdChangesBadNightCounts() {
        let before = (0..<7).map { night($0, [6.5]) }
        let after = (7..<14).map { night($0, [8]) }
        let group = started(7)
        let lenient = EffectAnalysis.analyze(group, nights: before + after, groups: [group], badNightThreshold: 6)
        #expect(lenient.before.badCount == 0)
        let strict = EffectAnalysis.analyze(group, nights: before + after, groups: [group], badNightThreshold: 7)
        #expect(strict.before.badCount == 7)
        #expect(strict.after.badCount == 0)
    }

    @Test func neighboringChangesBoundWindows() {
        var nights = (0..<20).map { night($0, [9]) }
        nights[12] = night(12, [2], excluded: true)
        let g1 = started(10, "A"), g2 = started(14, "B")
        let oneTime = InterventionGroup(date: Day.adding(5, to: start),
                                        events: [InterventionEvent(date: Day.adding(5, to: start), name: "Late night", kind: .oneTime)])
        let groups = [oneTime, g1, g2]

        let a = EffectAnalysis.analyze(g1, nights: nights, groups: groups)
        #expect(a.before.count == 7)  // capped at a week; one-time events don't bound the window
        #expect(a.after.nights.map { Day.between(start, $0.date) } == [10, 11, 13])  // 12 excluded, 14 is next change
        #expect(!a.isOngoing)
        #expect(a.overlapping.map(\.date) == [oneTime.date])
        #expect(a.hoursEvidence == .insufficient)
        #expect(a.hoursOutlook == nil)

        // Previous intervention only 3 included nights back: use a full week, reaching past it, and flag it.
        let b = EffectAnalysis.analyze(g2, nights: nights, groups: groups)
        #expect(b.before.nights.map { Day.between(start, $0.date) } == [6, 7, 8, 9, 10, 11, 13])
        #expect(b.previousInBaseline?.date == g1.date)
        #expect(!b.overlapping.contains { $0.date == g1.date })  // reported once, as the baseline warning
        #expect(b.after.count == 6)
        #expect(b.isOngoing)
        #expect(a.previousInBaseline == nil)
    }

    @Test func tooEarly() {
        let nights = (0..<12).map { night($0, [9]) }
        let group = started(10)
        let a = EffectAnalysis.analyze(group, nights: nights, groups: [group])
        #expect(a.after.count == 2)
        #expect(!a.hasResult)
        #expect(a.hasComparison)
        #expect(a.hoursOutlook == .unlikely)  // identical nights on both sides
    }

    @Test func earlyComparisonFromOneNight() throws {
        // A week of bad nights, then one good night: averages, Fisher p and a projection already.
        let nights = (0..<7).map { night($0, [4]) } + [night(7, [10])]
        let group = started(7)
        let a = EffectAnalysis.analyze(group, nights: nights, groups: [group])
        #expect(a.hasComparison && !a.hasResult)
        #expect(a.hoursDifference == 6)
        #expect(a.hoursTest == nil)  // Welch needs two nights on each side
        #expect(abs(try #require(a.badNightsP) - 0.125) < 1e-9)  // fisher_exact([[0, 1], [7, 0]])
        #expect(a.badNightsEvidence == .insufficient)
        // Strong evidence still needs 5 nights on each side, so at least 4 more.
        guard case .nights(let extra) = a.badNightsOutlook else { Issue.record("expected a projection"); return }
        #expect(extra >= 4)
        #expect(a.hoursOutlook == .nights(4))  // before is constant, so p = 0 once there are 5 after
    }

    @Test func hoursOutlookProjectsCurrentMeanAndVariance() throws {
        let beforeHours: [Double] = [8, 8.5, 9, 8, 8.5, 9, 8]
        let afterHours: [Double] = [8, 10, 9.5, 8.5, 9.5]
        let nights = beforeHours.enumerated().map { night($0.offset, [$0.element]) }
            + afterHours.enumerated().map { night(7 + $0.offset, [$0.element]) }
        let group = started(7)
        let a = EffectAnalysis.analyze(group, nights: nights, groups: [group])
        #expect(try #require(a.hoursTest).p >= 0.05)
        guard case .nights(let extra) = a.hoursOutlook else { Issue.record("expected a projection"); return }

        func p(_ count: Int) -> Double {
            Stats.welch(meanBefore: Stats.mean(beforeHours), varianceBefore: Stats.variance(beforeHours),
                        countBefore: 7, meanAfter: Stats.mean(afterHours),
                        varianceAfter: Stats.variance(afterHours), countAfter: Double(count)).p
        }
        #expect(p(5 + extra) < 0.05)
        #expect(p(5 + extra - 1) >= 0.05)
    }

    @Test func noDifferenceIsUnlikelyToBecomeSignificant() {
        let hours: [Double] = [8, 9, 10, 7, 9, 8]
        let nights = (hours + hours).enumerated().map { night($0.offset, [$0.element]) }
        let group = started(6)
        let a = EffectAnalysis.analyze(group, nights: nights, groups: [group])
        #expect(a.hoursOutlook == .unlikely)
        #expect(a.badNightsOutlook == .unlikely)
    }

    @Test func badNightsOutlookKeepsCurrentRate() {
        // Before: 4 of 7 bad. After: 1 of 6 bad (not significant yet).
        let before = (0..<7).map { night($0, $0 < 4 ? [4] : [9]) }
        let after = (7..<13).map { night($0, $0 == 7 ? [4] : [9]) }
        let group = started(7)
        let a = EffectAnalysis.analyze(group, nights: before + after, groups: [group])
        guard case .nights(let extra) = a.badNightsOutlook else { Issue.record("expected a projection"); return }
        let count = 6 + extra
        let bad = Int((Double(count) / 6).rounded())
        #expect(Stats.fisherExact(bad, count - bad, 4, 3) < 0.05)
    }

    @Test func summaryWelchMatchesArrayWelch() throws {
        let before: [Double] = [5, 9, 10, 8, 4, 10, 9.5], after: [Double] = [9, 9.5, 10, 9, 8.5, 9.25]
        let r = try #require(Stats.welch(before: before, after: after))
        let s = Stats.welch(meanBefore: Stats.mean(before), varianceBefore: Stats.variance(before), countBefore: 7,
                            meanAfter: Stats.mean(after), varianceAfter: Stats.variance(after), countAfter: 6,
                            confidenceInterval: false)
        #expect(abs(r.p - s.p) < 1e-12)
        #expect(s.ciLow.isNaN)
    }

    @Test func activeNames() {
        let d = start
        let events = [
            InterventionEvent(date: d, name: "Melatonin", kind: .started),
            InterventionEvent(date: Day.adding(1, to: d), name: "CBD", kind: .started),
            InterventionEvent(date: Day.adding(2, to: d), name: "Melatonin", kind: .stopped),
            InterventionEvent(date: Day.adding(3, to: d), name: "XR", kind: .oneTime),
        ]
        #expect(events.activeNames() == ["CBD"])
        #expect(events.activeNames(asOf: Day.adding(1, to: d)) == ["CBD", "Melatonin"])
    }
}
