import Foundation
import SwiftData

enum InterventionKind: String, CaseIterable, Codable, Identifiable {
    case started, stopped, changed, oneTime

    var id: String { rawValue }

    var label: String {
        switch self {
        case .started: "Started"
        case .stopped: "Stopped"
        case .changed: "Changed"
        case .oneTime: "One night"
        }
    }

    var symbol: String {
        switch self {
        case .started: "play.circle.fill"
        case .stopped: "stop.circle.fill"
        case .changed: "arrow.triangle.2.circlepath.circle.fill"
        case .oneTime: "1.circle.fill"
        }
    }
}

/// Something the family changed. `date` is the first morning it affects, so the
/// marker sits between the previous night and this one.
@Model
final class Intervention {
    var id: UUID
    var date: Date
    var name: String
    var kindRaw: String
    var details: String

    init(id: UUID = UUID(), date: Date, name: String, kind: InterventionKind, details: String = "") {
        self.id = id
        self.date = Day.start(date)
        self.name = name
        self.kindRaw = kind.rawValue
        self.details = details
    }

    var kind: InterventionKind {
        get { InterventionKind(rawValue: kindRaw) ?? .changed }
        set { kindRaw = newValue.rawValue }
    }

    var event: InterventionEvent {
        InterventionEvent(id: id, date: date, name: name, kind: kind, details: details)
    }
}

/// Plain value snapshot of an intervention.
struct InterventionEvent: Equatable, Hashable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var name: String
    var kind: InterventionKind
    var details: String = ""

    /// "Started Melatonin (after 4 hrs)"
    var title: String {
        details.isEmpty ? "\(kind.label) \(name)" : "\(kind.label) \(name) (\(details))"
    }

    static func == (a: Self, b: Self) -> Bool {
        a.date == b.date && a.name == b.name && a.kind == b.kind && a.details == b.details
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(date); hasher.combine(name); hasher.combine(kind); hasher.combine(details)
    }
}

extension Array where Element == InterventionEvent {
    /// Names of interventions currently in effect (started/changed and not stopped since).
    func activeNames(asOf date: Date = .distantFuture) -> [String] {
        var active: [String: Bool] = [:]
        for event in self.sorted(by: { $0.date < $1.date }) where event.date <= date {
            switch event.kind {
            case .started, .changed: active[event.name] = true
            case .stopped: active[event.name] = false
            case .oneTime: break
            }
        }
        return active.filter(\.value).map(\.key).sorted()
    }
}
