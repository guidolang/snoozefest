import Foundation
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

enum DataStore {
    static func snapshot(_ context: ModelContext) throws -> CSVCodec.Content {
        let entries = try context.fetch(FetchDescriptor<SleepEntry>())
        let interventions = try context.fetch(FetchDescriptor<Intervention>())
        return CSVCodec.Content(nights: entries.map(\.night), interventions: interventions.map(\.event))
    }

    static func deleteAll(_ context: ModelContext) throws {
        try context.delete(model: SleepEntry.self)
        try context.delete(model: Intervention.self)
        try context.save()
    }

    /// Replaces the whole database with the imported content.
    static func replaceAll(with content: CSVCodec.Content, in context: ModelContext) throws {
        try deleteAll(context)
        for night in content.nights {
            context.insert(SleepEntry(date: night.date, segments: night.segments,
                                      note: night.note, excludeFromAnalysis: night.excluded))
        }
        for event in content.interventions {
            context.insert(Intervention(date: event.date, name: event.name, kind: event.kind, details: event.details))
        }
        try context.save()
    }
}

/// A CSV export that the iOS share sheet can save or send as a file.
struct CSVExportFile: Transferable {
    var content: CSVCodec.Content

    var filename: String { "SnoozeFest-\(Day.iso(.now)).csv" }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .commaSeparatedText) { file in
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.filename)
            try CSVCodec.encode(file.content).write(to: url, atomically: true, encoding: .utf8)
            return SentTransferredFile(url)
        }
    }
}
