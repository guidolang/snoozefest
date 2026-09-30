import Charts
import SwiftData
import SwiftUI

struct InterventionDetailView: View {
    var group: InterventionGroup
    @Query(sort: \SleepEntry.date) private var entries: [SleepEntry]
    @Query(sort: \Intervention.date) private var interventions: [Intervention]
    @AppStorage(AppSettings.badNightThresholdKey) private var badNightThreshold = AppSettings.defaultBadNightThreshold

    var body: some View {
        let nights = entries.map(\.night)
        let groups = InterventionGroup.groups(from: interventions.map(\.event))
        let analysis = EffectAnalysis.analyze(group, nights: nights, groups: groups,
                                              badNightThreshold: badNightThreshold)

        List {
            Section { EffectCard(analysis: analysis) }

            if !analysis.before.nights.isEmpty || !analysis.after.nights.isEmpty {
                Section {
                    BeforeAfterChart(analysis: analysis)
                        .frame(height: 200)
                        .padding(.vertical, 8)
                } header: {
                    Text("Before vs. after")
                } footer: {
                    Text("Uninterrupted hours per night. Faded bars are bad nights.")
                }
            }

            if analysis.hasComparison {
                Section {
                    if let t = analysis.hoursTest {
                        LabeledContent("Difference in average", value: t.difference.signedHoursText)
                        LabeledContent("95% confidence interval", value: "\(t.ciLow.signedHoursText) … \(t.ciHigh.signedHoursText)")
                        LabeledContent("Welch's t", value: t.t.formatted(.number.precision(.fractionLength(2))))
                        LabeledContent("Degrees of freedom", value: t.degreesOfFreedom.formatted(.number.precision(.fractionLength(1))))
                        LabeledContent("p-value (uninterrupted sleep)", value: t.p.pValueText)
                        if !t.cohensD.isNaN {
                            LabeledContent("Effect size (Cohen's d)", value: t.cohensD.formatted(.number.precision(.fractionLength(2))))
                        }
                    }
                    LabeledContent("Before: bad / good nights",
                                   value: "\(analysis.before.badCount) / \(analysis.before.count - analysis.before.badCount)")
                    LabeledContent("After: bad / good nights",
                                   value: "\(analysis.after.badCount) / \(analysis.after.count - analysis.after.badCount)")
                    if let p = analysis.badNightsP {
                        LabeledContent("p-value (Fisher's exact)", value: p.pValueText)
                    }
                    LabeledContent("SD before / after", value: "\(analysis.before.sdHours.formatted(.number.precision(.fractionLength(2)))) / \(analysis.after.sdHours.formatted(.number.precision(.fractionLength(2)))) h")
                } header: {
                    Text("Statistics")
                }
            }
        }
        .navigationTitle(group.events.first?.name ?? "Intervention")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BeforeAfterChart: View {
    var analysis: EffectAnalysis

    var body: some View {
        let before = analysis.before, after = analysis.after
        Chart {
            ForEach(before.nights, id: \.date) { night in
                BarMark(x: .value("Night", night.date, unit: .day), y: .value("Hours", night.uninterruptedHours))
                    .foregroundStyle(Theme.before.opacity(night.isBad(threshold: before.badNightThreshold) ? 0.4 : 0.8))
            }
            ForEach(after.nights, id: \.date) { night in
                BarMark(x: .value("Night", night.date, unit: .day), y: .value("Hours", night.uninterruptedHours))
                    .foregroundStyle(Theme.after.opacity(night.isBad(threshold: after.badNightThreshold) ? 0.4 : 1))
            }
            if let first = before.nights.first?.date, let last = before.nights.last?.date, !before.meanHours.isNaN {
                RuleMark(xStart: .value("Start", first), xEnd: .value("End", Day.adding(1, to: last)),
                         y: .value("Mean", before.meanHours))
                    .foregroundStyle(Theme.before)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("avg \(before.meanHours.formatted(.number.precision(.fractionLength(1))))h")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
            }
            if let first = after.nights.first?.date, let last = after.nights.last?.date, !after.meanHours.isNaN {
                RuleMark(xStart: .value("Start", first), xEnd: .value("End", Day.adding(1, to: last)),
                         y: .value("Mean", after.meanHours))
                    .foregroundStyle(Theme.after)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("avg \(after.meanHours.formatted(.number.precision(.fractionLength(1))))h")
                            .font(.caption2).foregroundStyle(Theme.after)
                    }
            }
            RuleMark(x: .value("Intervention", analysis.group.date))
                .foregroundStyle(Theme.intervention)
                .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartYScale(domain: 0...max(12, (before.nights + after.nights).map(\.uninterruptedHours).max() ?? 0))
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel() }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .stride(by: 3)) { value in
                AxisGridLine()
                AxisValueLabel { if let h = value.as(Double.self) { Text("\(Int(h))h") } }
            }
        }
        .accessibilityLabel("Uninterrupted sleep per night before and after the intervention")
    }
}

struct MethodologyView: View {
    @AppStorage(AppSettings.badNightThresholdKey) private var badNightThreshold = AppSettings.defaultBadNightThreshold
    @AppStorage(AppSettings.movingAverageKey) private var movingAverageNights = AppSettings.defaultMovingAverage

    var body: some View {
        let week = EffectAnalysis.beforeNights
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("The chart",
                        "Each bar is one night, dated by the morning your child woke up: the dark part is the first stretch of sleep, the light part is sleep after waking, and grey bars are nights excluded from analysis. The line is the average first stretch over the last \(movingAverageNights) calendar days (set in Settings), using the nights you logged and didn't exclude. Red lines mark interventions; dashed ones are one-time. The two tiles summarise the period on screen, leaving out excluded nights.")
                section("What gets compared",
                        "Each intervention compares every night since it started (up to the next intervention, or today) with the nights just before it. If the previous intervention was \(week) or fewer nights earlier, the before period is the \(week) nights just before this one, even though that reaches back past the previous intervention; you'll see a warning, because its effect may be mixed in. Otherwise the before period is \(week) nights while there are \(week) or fewer after, then grows to match the number of after nights, but never reaches back past the previous intervention. The two sides don't need the same number of nights: both tests handle unequal groups. One-time interventions don't split the periods: they compare their single night with the nights before, without a statistical test. Nights marked “Exclude from analysis” and nights you didn't log are skipped.")
                section("Uninterrupted sleep",
                        "The hours slept before the first waking are compared with Welch's t-test, which works even when one period is much more variable than the other. It needs at least 2 nights on each side. Sleep after a night waking isn't counted. The 95% range is the confidence interval for the difference.")
                section("Bad nights",
                        "A night is bad when your child woke up during the night, or when the first stretch of sleep was \(badNightThreshold.hoursText) hours or less (adjustable in Settings). The share of bad nights before vs. after is compared with Fisher's exact test, which is reliable for small numbers of nights (a chi-square test isn't) and works from the first night.")
                section("Reading the badges",
                        "Averages and p-values appear from the first night after an intervention, but the badges wait until there are \(Evidence.minimumNights) nights on each side.\nStrong evidence: p < 0.05.\nSuggestive: p < 0.20.\nNo clear difference: p ≥ 0.20.\nNot enough data: fewer than \(Evidence.minimumNights) nights on one side.")
                section("Nights until strong evidence",
                        "For an intervention that's still running (no later intervention yet), SnoozeFest estimates how many more nights you'd need to log to reach strong evidence: p < 0.05 with at least \(Evidence.minimumNights) nights on each side. It assumes both periods keep their current average and spread (with a single night after, its spread is assumed to match the before period's), and that the before period grows as the rules above allow. It's a rough guide: early differences often shrink as more nights come in, and checking repeatedly until something turns significant makes false alarms more likely. If it would take more than a year, SnoozeFest says it's unlikely.")
                section("Things to keep in mind",
                        "Sleep naturally varies, and nights aren't fully independent of each other. Travel, illness, school holidays and several simultaneous interventions can all create or hide effects. Trying one intervention at a time makes results much clearer.")
                section("Not medical advice",
                        "SnoozeFest helps you organise observations to discuss with your child's doctor. It doesn't diagnose or recommend treatment.")
            }
            .padding()
        }
        .navigationTitle("How the statistics work")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(text).font(.callout).foregroundStyle(.secondary)
        }
    }
}
