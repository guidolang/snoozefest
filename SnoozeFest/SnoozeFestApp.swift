import SwiftData
import SwiftUI

@main
struct SnoozeFestApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [SleepEntry.self, Intervention.self])
    }
}

struct RootView: View {
    #if DEBUG
    @Environment(\.modelContext) private var context
    #endif

    var body: some View {
        HomeView()
        #if DEBUG
        .task { debugImportIfRequested() }
        #endif
    }

    #if DEBUG
    /// Development aid: `SNOOZEFEST_IMPORT=/path/to/file.csv` replaces the store on launch.
    private func debugImportIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["SNOOZEFEST_IMPORT"],
              let text = try? String(contentsOfFile: path, encoding: .utf8),
              let content = try? CSVCodec.decode(text) else { return }
        try? DataStore.replaceAll(with: content, in: context)
    }
    #endif
}

enum AppSettings {
    static let movingAverageKey = "movingAverageNights"
    static let badNightThresholdKey = "badNightThreshold"
    static let defaultMovingAverage = 7
    static let defaultBadNightThreshold = 6.0
}
