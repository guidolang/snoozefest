import SwiftData
import SwiftUI

struct SegmentDraft: Identifiable, Equatable {
    var id = UUID()
    var hours: Double
}

struct InterventionDraft:Identifiable, Equatable {
    var id = UUID()
    var existingID: UUID?
    var name = ""
    var kind = InterventionKind.started
    var details = ""
}

/// Sheet for logging (or editing) one night plus any interventions that started that evening.
struct LogNightView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Intervention.date) private var allInterventions: [Intervention]
    @AppStorage(AppSettings.badNightThresholdKey) private var badNightThreshold = AppSettings.defaultBadNightThreshold

    /// Morning of the night being logged (fixed; pick another night from the list).
    private let date: Date
    /// Called after saving, with true when the saved night is good and wasn't before.
    private let onSave: (Bool) -> Void

    @State private var segments: [SegmentDraft] = [SegmentDraft(hours: 9)]
    @State private var note = ""
    @State private var exclude = false
    @State private var drafts: [InterventionDraft] = []
    @State private var existingEntry: SleepEntry?
    @State private var editingDraft: InterventionDraft?
    @State private var confirmDelete = false

    static let maxWakings = CSVCodec.maxSegments - 1

    init(date: Date, onSave: @escaping (Bool) -> Void = { _ in }) {
        self.date = Day.start(date)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach($segments) { $segment in
                        let index = segments.firstIndex { $0.id == segment.id } ?? 0
                        HoursRow(
                            title: index == 0 ? "Slept" : "Slept again after waking #\(index)",
                            value: $segment.hours,
                            onRemove: index == 0 ? nil : { [id = segment.id] in segments.removeAll { $0.id == id } }
                        )
                    }
                    if segments.count <= Self.maxWakings {
                        Button {
                            withAnimation { segments.append(SegmentDraft(hours: 2)) }
                        } label: {
                            Label("Add night waking", systemImage: "plus.circle")
                        }
                    }
                } header: {
                    Text("Night of \(Day.nightLabel(forMorning: date))")
                } footer: {
                    HStack {
                        Text(segments.count > 1 ? "Woke up \(segments.count - 1)× during the night" : "Slept through")
                        Spacer()
                        Text("Total \(hours.reduce(0, +).hoursText) h").fontWeight(.semibold)
                    }
                }

                Section {
                    ForEach(drafts) { draft in
                        Button { editingDraft = draft } label: {
                            InterventionRow(event: InterventionEvent(date: date, name: draft.name, kind: draft.kind, details: draft.details))
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { drafts.remove(atOffsets: $0) }
                    Button {
                        editingDraft = InterventionDraft()
                    } label: {
                        Label("Add intervention", systemImage: "flag")
                    }
                } header: {
                    Text("Interventions")
                } footer: {
                    Text("Anything you started, stopped or changed on the evening before this morning.")
                }

                Section {
                    TextField("Note (optional)", text: $note, axis: .vertical)
                    Toggle("Exclude from analysis", isOn: $exclude)
                } footer: {
                    Text("Exclude unusual nights (travel, illness, forgotten medication) so they don't skew the statistics. They still appear in charts.")
                }

                if existingEntry != nil {
                    Section {
                        Button("Delete this night", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.fontWeight(.semibold)
                }
            }
            .sheet(item: $editingDraft) { draft in
                InterventionEditor(
                    draft: draft,
                    knownNames: knownNames,
                    activeNames: allInterventions.map(\.event).activeNames(asOf: Day.adding(-1, to: date)),
                    onSave: { saved in
                        if let i = drafts.firstIndex(where: { $0.id == saved.id }) { drafts[i] = saved } else { drafts.append(saved) }
                    },
                    onDelete: drafts.contains { $0.id == draft.id } ? { drafts.removeAll { $0.id == draft.id } } : nil
                )
            }
            .confirmationDialog("Delete this night?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let existingEntry { context.delete(existingEntry) }
                    try? context.save()
                    dismiss()
                }
            }
            .onAppear { load() }
        }
    }

    private var hours: [Double] { segments.map(\.hours) }

    private var knownNames: [String] {
        Array(Set(allInterventions.map(\.name))).sorted()
    }

    private func load() {
        let day = Day.start(date)
        let entry = try? context.fetch(FetchDescriptor<SleepEntry>(predicate: #Predicate { $0.date == day })).first
        existingEntry = entry
        if let entry {
            segments = entry.segments.map { SegmentDraft(hours: $0) }
            note = entry.note
            exclude = entry.excludeFromAnalysis
        } else {
            segments = [SegmentDraft(hours: segments.first?.hours ?? 9)]
            note = ""
            exclude = false
        }
        drafts = allInterventions.filter { $0.date == day }.map {
            InterventionDraft(existingID: $0.id, name: $0.name, kind: $0.kind, details: $0.details)
        }
    }

    private func save() {
        let day = Day.start(date)
        let wasGood = existingEntry.map { !$0.night.isBad(threshold: badNightThreshold) } ?? false
        let isGood = !Night(date: day, segments: hours).isBad(threshold: badNightThreshold)
        if let entry = existingEntry {
            entry.segments = hours
            entry.note = note
            entry.excludeFromAnalysis = exclude
        } else {
            context.insert(SleepEntry(date: day, segments: hours, note: note, excludeFromAnalysis: exclude))
        }
        let keptIDs = Set(drafts.compactMap(\.existingID))
        for intervention in allInterventions where intervention.date == day && !keptIDs.contains(intervention.id) {
            context.delete(intervention)
        }
        for draft in drafts where !draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let name = draft.name.trimmingCharacters(in: .whitespaces)
            if let id = draft.existingID, let model = allInterventions.first(where: { $0.id == id }) {
                model.name = name
                model.kind = draft.kind
                model.details = draft.details
            } else {
                context.insert(Intervention(date: day, name: name, kind: draft.kind, details: draft.details))
            }
        }
        try? context.save()
        onSave(isGood && !wasGood)
        dismiss()
    }
}

/// A row that shows hours and expands into a wheel picker (0–16 h in 15-minute steps).
struct HoursRow: View {
    var title: String
    @Binding var value: Double
    var onRemove: (() -> Void)?
    @State private var expanded = false

    private static let options = stride(from: 0.0, through: 16.0, by: 0.25).map { $0 }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if let onRemove {
                    Button(action: { withAnimation { onRemove() } }) {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove waking")
                }
                Text(title)
                Spacer()
                Button {
                    withAnimation { expanded.toggle() }
                } label: {
                    Text("\(value.hoursText) h")
                        .monospacedDigit()
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.accentColor.opacity(expanded ? 0.2 : 0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("\(title): \(value.hoursText) hours")
                .accessibilityHint("Double tap to change")
            }
            if expanded {
                Picker(title, selection: $value) {
                    ForEach(Self.options, id: \.self) { Text("\($0.hoursText) h").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
            }
        }
    }
}
