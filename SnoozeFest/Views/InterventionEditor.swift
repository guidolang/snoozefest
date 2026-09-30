import SwiftData
import SwiftUI

/// Edits a single intervention draft (used from the log sheet and the standalone sheet).
struct InterventionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: InterventionDraft
    var knownNames: [String]
    var activeNames: [String]
    var date: Binding<Date>?
    var onSave: (InterventionDraft) -> Void
    var onDelete: (() -> Void)?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $draft.kind) {
                        ForEach(InterventionKind.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(kindExplanation)
                }

                Section("What") {
                    TextField("e.g. Melatonin, Magnesium, bedtime routine", text: $draft.name)
                        .textInputAutocapitalization(.sentences)
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(suggestions, id: \.self) { name in
                                    Button(name) { draft.name = name }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                    TextField("Details, e.g. dose (optional)", text: $draft.details)
                }

                if let date {
                    Section {
                        DatePicker("First morning affected", selection: date, in: ...Self.latestDate, displayedComponents: .date)
                    } footer: {
                        Text("Night of \(Day.nightLabel(forMorning: date.wrappedValue)). The marker appears just before this night in charts. Pick tomorrow for an intervention you're starting today.")
                    }
                }

                if let onDelete {
                    Section {
                        Button("Delete intervention", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Intervention")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        draft.name = draft.name.trimmingCharacters(in: .whitespaces)
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }

    /// End of tomorrow, so a change made today can be dated to the morning it first affects.
    static var latestDate: Date { Day.adding(2, to: Day.today).addingTimeInterval(-1) }

    private var kindExplanation: String {
        switch draft.kind {
        case .started: "Something new you're trying from now on."
        case .stopped: "Something you've stopped doing."
        case .changed: "A change to something ongoing, like a new dose or brand."
        case .oneTime: "Tried for a single night only."
        }
    }

    private var suggestions: [String] {
        let base = (draft.kind == .stopped || draft.kind == .changed) ? activeNames + knownNames : knownNames
        var seen = Set<String>()
        let unique = base.filter { seen.insert($0).inserted }
        let query = draft.name.trimmingCharacters(in: .whitespaces)
        if query.isEmpty { return Array(unique.prefix(8)) }
        return unique.filter { $0.localizedCaseInsensitiveContains(query) && $0 != query }
    }
}

/// Standalone add/edit of an intervention, writing straight to the store.
struct InterventionSheet: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Intervention.date) private var all: [Intervention]
    var existing: Intervention?
    @State private var date: Date

    init(existing: Intervention?) {
        self.existing = existing
        _date = State(initialValue: existing?.date ?? Self.defaultDate)
    }

    /// In the morning a new change most likely affected last night; from noon on, it'll affect tonight.
    static var defaultDate: Date {
        Day.calendar.component(.hour, from: .now) < 12 ? Day.today : Day.adding(1, to: Day.today)
    }

    var body: some View {
        InterventionEditor(
            draft: InterventionDraft(existingID: existing?.id, name: existing?.name ?? "",
                                     kind: existing?.kind ?? .started, details: existing?.details ?? ""),
            knownNames: Array(Set(all.map(\.name))).sorted(),
            activeNames: all.map(\.event).activeNames(),
            date: $date,
            onSave: save,
            onDelete: existing.map { model in { context.delete(model); try? context.save() } }
        )
    }

    private func save(_ draft: InterventionDraft) {
        if let existing {
            existing.name = draft.name
            existing.kind = draft.kind
            existing.details = draft.details
            existing.date = Day.start(date)
        } else {
            context.insert(Intervention(date: date, name: draft.name, kind: draft.kind, details: draft.details))
        }
        try? context.save()
    }
}
