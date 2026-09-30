import Foundation

/// Helpers for working with calendar days. Every stored date in the app is the
/// local start of day of the *morning* a night ended ("recorded morning of").
enum Day {
    static var calendar: Calendar { Calendar.current }

    static func start(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    static var today: Date { start(.now) }

    static func adding(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: start(date)) ?? date
    }

    /// Whole days from `a` to `b` (positive when `b` is later).
    static func between(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: start(a), to: start(b)).day ?? 0
    }

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func iso(_ date: Date) -> String {
        isoFormatter.timeZone = calendar.timeZone
        return isoFormatter.string(from: date)
    }

    static func parseISO(_ string: String) -> Date? {
        isoFormatter.timeZone = calendar.timeZone
        return isoFormatter.date(from: string.trimmingCharacters(in: .whitespaces)).map(start)
    }

    /// "Night of Mon, Apr 1 → Tue, Apr 2"
    static func nightLabel(forMorning morning: Date) -> String {
        let evening = adding(-1, to: morning)
        let style = Date.FormatStyle().weekday(.abbreviated).month(.abbreviated).day()
        return "\(evening.formatted(style)) → \(morning.formatted(style))"
    }
}

extension Double {
    /// Formats hours compactly: 9 → "9", 9.25 → "9.25", 9.5 → "9.5".
    var hoursText: String {
        formatted(.number.precision(.fractionLength(0...2)))
    }
}
