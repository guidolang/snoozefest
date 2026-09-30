import Foundation
import SwiftData

/// One night of sleep, keyed by the morning it ended.
@Model
final class SleepEntry {
    /// Local start of day of the wake-up morning.
    @Attribute(.unique) var date: Date
    /// Sleep stretches in hours. `[5.5, 4]` = slept 5.5h, woke up, slept 4h more.
    var segments: [Double]
    var note: String
    /// Unusual nights (travel, illness, forgotten meds) can be left out of statistics.
    var excludeFromAnalysis: Bool

    init(date: Date, segments: [Double], note: String = "", excludeFromAnalysis: Bool = false) {
        self.date = Day.start(date)
        self.segments = segments
        self.note = note
        self.excludeFromAnalysis = excludeFromAnalysis
    }

    var totalHours: Double { segments.reduce(0, +) }
    var wakeCount: Int { max(segments.count - 1, 0) }
    var isInterrupted: Bool { segments.count > 1 }
    var uninterruptedHours: Double { segments.first ?? 0 }

    var night: Night {
        Night(date: date, segments: segments, excluded: excludeFromAnalysis, note: note)
    }
}

/// Plain value snapshot of a night, used by analysis, charts and CSV.
struct Night: Equatable, Hashable {
    var date: Date
    var segments: [Double]
    var excluded: Bool = false
    var note: String = ""

    var totalHours: Double { segments.reduce(0, +) }
    var isInterrupted: Bool { segments.count > 1 }
    /// Hours slept before the first waking.
    var uninterruptedHours: Double { segments.first ?? 0 }

    /// A bad night has a waking, or a first stretch of `threshold` hours or less.
    func isBad(threshold: Double) -> Bool {
        isInterrupted || uninterruptedHours <= threshold
    }
}
