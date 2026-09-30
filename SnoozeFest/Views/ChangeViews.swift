import SwiftUI

struct HistoryRow: View {
    var analysis: EffectAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(analysis.group.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Spacer()
                Text(analysis.group.date.formatted(.dateTime.month(.abbreviated).day().year(.twoDigits)))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if analysis.isOneTime {
                if let night = analysis.after.nights.first {
                    Text("One night: \(night.uninterruptedHours.hoursText) h uninterrupted vs. \(analysis.before.meanHours.formatted(.number.precision(.fractionLength(1)))) h typical")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if analysis.hasComparison {
                HStack(spacing: 12) {
                    metric(analysis.hoursDifference.signedHoursText, analysis.hoursEvidence, "uninterrupted")
                    metric(analysis.badNightsDifference.signedPointsText, analysis.badNightsEvidence, "bad nights")
                }
            } else {
                Text("Not enough nights to compare yet").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func metric(_ value: String, _ evidence: Evidence, _ label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: evidence.symbol).foregroundStyle(evidence.color)
            Text(value).monospacedDigit().fontWeight(.medium)
            Text(label).foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

/// Before/after comparison for one change: two metrics with evidence badges and caveats.
struct EffectCard: View {
    var analysis: EffectAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(analysis.group.events) { event in
                    Label(event.title, systemImage: event.kind.symbol)
                        .font(.headline)
                        .foregroundStyle(Theme.intervention)
                }
                Text("\(analysis.group.date.formatted(date: .long, time: .omitted)) · \(ago)")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if analysis.isOneTime {
                oneTimeSummary
            } else if !analysis.hasComparison {
                tooEarly
            } else {
                MetricComparison(
                    title: "Uninterrupted sleep",
                    before: "\(analysis.before.meanHours.formatted(.number.precision(.fractionLength(1)))) h",
                    after: "\(analysis.after.meanHours.formatted(.number.precision(.fractionLength(1)))) h",
                    change: analysis.hoursDifference.signedHoursText,
                    isImprovement: analysis.hoursDifference > 0,
                    detail: analysis.hoursTest.map {
                        "p = \($0.p.pValueText) · 95% range: \($0.ciLow.signedHoursText) to \($0.ciHigh.signedHoursText)"
                    } ?? "p-value needs at least 2 nights on each side.",
                    evidence: analysis.hoursEvidence,
                    outlook: analysis.hoursOutlook
                )
                MetricComparison(
                    title: "Bad nights",
                    before: "\(analysis.before.badRate.percentText) (\(analysis.before.badCount)/\(analysis.before.count))",
                    after: "\(analysis.after.badRate.percentText) (\(analysis.after.badCount)/\(analysis.after.count))",
                    change: analysis.badNightsDifference.signedPointsText,
                    isImprovement: analysis.badNightsDifference < 0,
                    detail: (analysis.badNightsP.map { "p = \($0.pValueText) · " } ?? "")
                        + "Woke up, or first stretch ≤ \(analysis.before.badNightThreshold.hoursText) h.",
                    evidence: analysis.badNightsEvidence,
                    outlook: analysis.badNightsOutlook
                )
                Text("Based on \(analysis.before.count) nights before vs. \(analysis.after.count) night\(analysis.after.count == 1 ? "" : "s") after.")
                    .font(.caption).foregroundStyle(.secondary)
                if !analysis.hasResult {
                    Label("Early numbers: evidence ratings start once there are \(Evidence.minimumNights) nights on each side.",
                          systemImage: "hourglass")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            warnings
        }
        .padding(.vertical, 6)
    }

    private var ago: String {
        let days = Day.between(analysis.group.date, Day.today)
        switch days {
        case ..<0: return days == -1 ? "starts tomorrow" : "in \(-days) days"
        case 0: return "today"
        case 1: return "1 day ago"
        default: return "\(days) days ago"
        }
    }

    private var tooEarly: some View {
        Label {
            Text(analysis.after.count == 0
                 ? "No nights logged since this intervention yet."
                 : "No nights logged before this intervention to compare with.")
        } icon: {
            Image(systemName: "hourglass")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder private var oneTimeSummary: some View {
        if let night = analysis.after.nights.first {
            Text("That night: \(night.segments.map(\.hoursText).joined(separator: " + ")) = \(night.totalHours.hoursText) h. Typical before: \(analysis.before.meanHours.formatted(.number.precision(.fractionLength(1)))) h uninterrupted, bad nights \(analysis.before.badRate.percentText).")
                .font(.subheadline)
            Text("A single night can't show a reliable effect. Log it as “Started” if you keep using it.")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("No night logged for this date.").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var warnings: some View {
        if let previous = analysis.previousInBaseline, !analysis.isOneTime {
            Label {
                Text("The previous intervention (\(previous.title), \(previous.date.formatted(.dateTime.month(.abbreviated).day()))) falls within the \(analysis.before.count) “before” nights, so its effect may be mixed into the comparison.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.caption)
        }
        let others = analysis.overlapping.flatMap(\.events)
        if !others.isEmpty && !analysis.isOneTime {
            Label {
                Text("Other interventions happened during this comparison (\(others.map(\.title).joined(separator: ", "))), so their effects may be mixed in.")
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.caption)
        }
        if analysis.group.events.count > 1 && !analysis.isOneTime {
            Label("Several interventions started on the same day; their effects can't be separated.", systemImage: "square.stack.3d.up")
                .font(.caption).foregroundStyle(.secondary)
        }
        if analysis.hasResult && analysis.n < 7 {
            Label("Few nights compared, so results can swing a lot.", systemImage: "info.circle")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct MetricComparison: View {
    var title: String
    var before: String
    var after: String
    var change: String
    var isImprovement: Bool
    var detail: String?
    var evidence: Evidence
    var outlook: SignificanceOutlook?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                EvidenceBadge(evidence: evidence, compact: true)
            }
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text("Before").font(.caption2).foregroundStyle(.secondary)
                    Text(before).monospacedDigit()
                }
                Image(systemName: "arrow.right").foregroundStyle(.secondary).font(.caption)
                VStack(alignment: .leading) {
                    Text("After").font(.caption2).foregroundStyle(.secondary)
                    Text(after).monospacedDigit().fontWeight(.semibold)
                }
                Spacer()
                Text(change).font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(changeColor)
            }
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            if evidence != .insufficient {  // the badge already says "Not enough data"
                Text(evidence.label).font(.caption).foregroundStyle(evidence.color)
            }
            if let outlookText {
                Label(outlookText, systemImage: "calendar.badge.clock")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var outlookText: String? {
        switch outlook {
        case .nights(let n): "At this rate, about \(n) more night\(n == 1 ? "" : "s") until strong evidence."
        case .unlikely: "At this rate, unlikely to reach strong evidence within a year."
        case .reached, nil: nil
        }
    }

    /// Green/red only when there's at least suggestive evidence; otherwise neutral.
    private var changeColor: Color {
        switch evidence {
        case .strong, .suggestive: isImprovement ? .green : .red
        case .none, .insufficient: .primary
        }
    }
}
