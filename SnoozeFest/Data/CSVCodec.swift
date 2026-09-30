import Foundation

/// Reads and writes the SnoozeFest CSV format: one file, one row per night or
/// intervention, distinguished by `record_type`.
enum CSVCodec {
    static let maxSegments = 4

    static let header = [
        "record_type", "date", "segment_1", "segment_2", "segment_3", "segment_4",
        "total_hours", "interrupted", "excluded",
        "intervention_kind", "intervention_name", "intervention_details", "note",
    ]

    struct Content: Equatable {
        var nights: [Night] = []
        var interventions: [InterventionEvent] = []
    }

    struct ImportError: LocalizedError {
        var line: Int
        var message: String
        var errorDescription: String? { line > 0 ? "Line \(line): \(message)" : message }
    }

    // MARK: - Encoding

    static func encode(_ content: Content) -> String {
        var rows: [[String]] = [header]
        for night in content.nights.sorted(by: { $0.date < $1.date }) {
            var segments = night.segments.map(number)
            segments += Array(repeating: "", count: max(0, maxSegments - segments.count))
            rows.append(["night", Day.iso(night.date)] + segments + [
                number(night.totalHours), String(night.isInterrupted), String(night.excluded),
                "", "", "", night.note,
            ])
        }
        for event in content.interventions.sorted(by: { ($0.date, $0.name) < ($1.date, $1.name) }) {
            rows.append(["intervention", Day.iso(event.date), "", "", "", "", "", "", "",
                         event.kind.rawValue, event.name, event.details, ""])
        }
        return rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    private static func number(_ x: Double) -> String {
        x.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...4)))
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    // MARK: - Decoding

    static func decode(_ text: String) throws -> Content {
        let rows = parseRows(text)
        guard let headerRow = rows.first else { throw ImportError(line: 0, message: "The file is empty.") }
        let columns = Dictionary(headerRow.enumerated().map {
            ($0.element.trimmingCharacters(in: .whitespaces).lowercased(), $0.offset)
        }, uniquingKeysWith: { first, _ in first })
        for required in ["record_type", "date"] where columns[required] == nil {
            throw ImportError(line: 1, message: "Missing “\(required)” column. Is this a SnoozeFest export?")
        }
        let segmentColumns = columns.keys.filter { $0.hasPrefix("segment_") }
            .sorted { Int($0.dropFirst(8)) ?? 0 < Int($1.dropFirst(8)) ?? 0 }
            .compactMap { columns[$0] }

        var content = Content()
        var seenDates = Set<Date>()
        for (index, row) in rows.enumerated().dropFirst() {
            let line = index + 1
            func field(_ name: String) -> String {
                guard let i = columns[name], i < row.count else { return "" }
                return row[i].trimmingCharacters(in: .whitespaces)
            }
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            guard let date = Day.parseISO(field("date")) else {
                throw ImportError(line: line, message: "Invalid date “\(field("date"))” (expected YYYY-MM-DD).")
            }
            switch field("record_type").lowercased() {
            case "night":
                var segments: [Double] = []
                for i in segmentColumns where i < row.count {
                    let value = row[i].trimmingCharacters(in: .whitespaces)
                    if value.isEmpty { continue }
                    guard let hours = Double(value), hours >= 0, hours <= 24 else {
                        throw ImportError(line: line, message: "Invalid hours “\(value)”.")
                    }
                    segments.append(hours)
                }
                if segments.isEmpty, let total = Double(field("total_hours")) { segments = [total] }
                guard !segments.isEmpty else { throw ImportError(line: line, message: "Night has no hours.") }
                guard seenDates.insert(date).inserted else {
                    throw ImportError(line: line, message: "Duplicate night for \(Day.iso(date)).")
                }
                content.nights.append(Night(date: date, segments: segments,
                                            excluded: field("excluded").lowercased() == "true",
                                            note: field("note")))
            case "intervention":
                let name = field("intervention_name")
                guard !name.isEmpty else { throw ImportError(line: line, message: "Intervention has no name.") }
                guard let kind = InterventionKind(rawValue: field("intervention_kind")) else {
                    throw ImportError(line: line, message: "Unknown intervention kind “\(field("intervention_kind"))”.")
                }
                content.interventions.append(InterventionEvent(date: date, name: name, kind: kind,
                                                               details: field("intervention_details")))
            case let other:
                throw ImportError(line: line, message: "Unknown record type “\(other)”.")
            }
        }
        return content
    }

    /// RFC 4180 parser: quoted fields may contain commas, quotes ("") and newlines.
    static func parseRows(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text.replacingOccurrences(of: "\r\n", with: "\n")).makeIterator()
        var pending: Character? = chars.next()
        if pending == "\u{FEFF}" { pending = chars.next() }  // byte-order mark
        while let c = pending {
            pending = chars.next()
            if inQuotes {
                if c == "\"" {
                    if pending == "\"" { field.append("\""); pending = chars.next() } else { inQuotes = false }
                } else {
                    field.append(c)
                }
            } else {
                switch c {
                case "\"": inQuotes = true
                case ",": row.append(field); field = ""
                case "\n", "\r": row.append(field); rows.append(row); row = []; field = ""
                default: field.append(c)
                }
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}
