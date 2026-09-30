import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var entries: [SleepEntry]
    @Query private var interventions: [Intervention]
    @AppStorage(AppSettings.movingAverageKey) private var movingAverageNights = AppSettings.defaultMovingAverage
    @AppStorage(AppSettings.badNightThresholdKey) private var badNightThreshold = AppSettings.defaultBadNightThreshold

    @State private var showImporter = false
    @State private var pendingImport: CSVCodec.Content?
    @State private var importError: String?
    @State private var confirmDeleteAll = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ShareLink(item: exportFile, preview: SharePreview("SnoozeFest data (\(entries.count) nights)")) {
                        Label("Export data as CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty && interventions.isEmpty)
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import CSV…", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("Backup")
                } footer: {
                    Text("\(entries.count) nights and \(interventions.count) interventions stored on this iPhone. Export regularly to keep a backup in Files, iCloud Drive or email. Importing replaces all current data.")
                }

                Section {
                    Stepper("Moving average: \(movingAverageNights) nights", value: $movingAverageNights, in: 3...30)
                    Stepper("Bad night: ≤ \(badNightThreshold.hoursText) h", value: $badNightThreshold, in: 1...12, step: 0.5)
                } header: {
                    Text("Analysis")
                } footer: {
                    Text("A night counts as bad when your child wakes up during the night, or when the first stretch of sleep is \(badNightThreshold.hoursText) hours or less.")
                }

                Section {
                    NavigationLink("How the statistics work") { MethodologyView() }
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                } header: {
                    Text("About")
                } footer: {
                    Text("Your data never leaves this device unless you export it. SnoozeFest is not a medical device and doesn't provide medical advice.")
                }

                Section {
                    Button("Delete all data", role: .destructive) { confirmDeleteAll = true }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.commaSeparatedText, .plainText]) { result in
                handleImport(result)
            }
            .alert("Replace all data?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
                Button("Replace", role: .destructive) { applyImport() }
                Button("Cancel", role: .cancel) { pendingImport = nil }
            } message: {
                if let pendingImport {
                    Text("The file contains \(pendingImport.nights.count) nights and \(pendingImport.interventions.count) interventions. This replaces the \(entries.count) nights and \(interventions.count) interventions currently in the app.")
                }
            }
            .alert("Couldn't import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importError ?? "")
            }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .confirmationDialog("Delete all nights and interventions?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    try? DataStore.deleteAll(context)
                }
            } message: {
                Text("This can't be undone. Consider exporting a backup first.")
            }
        }
    }

    private var exportFile: CSVExportFile {
        CSVExportFile(content: CSVCodec.Content(nights: entries.map(\.night), interventions: interventions.map(\.event)))
    }

    private func handleImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let text = try String(contentsOf: url, encoding: .utf8)
            pendingImport = try CSVCodec.decode(text)
        } catch {
            importError = error.localizedDescription
        }
    }

    private func applyImport() {
        guard let content = pendingImport else { return }
        pendingImport = nil
        do {
            try DataStore.replaceAll(with: content, in: context)
            message = "Imported \(content.nights.count) nights and \(content.interventions.count) interventions."
        } catch {
            importError = error.localizedDescription
        }
    }
}
