import SwiftUI

/// Adds or edits a term: how it's written, and the spellings it replaces.
struct TermEditor: View {
    enum Target: Identifiable {
        case new
        case existing(VocabularyTerm)

        var id: String {
            switch self {
            case .new: return "new"
            case .existing(let term): return term.id.uuidString
            }
        }
    }

    let target: Target
    let store: VocabularyStore
    @Environment(\.dismiss) private var dismiss
    @State private var term = ""
    @State private var heardAs = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Add a term" : "Edit term")
                .font(Theme.title)
            Form {
                TextField("Term", text: $term, prompt: Text("Paramount+"))
                    .accessibilityIdentifier("vocabulary.term")
                TextField("Heard as", text: $heardAs, prompt: Text("paramount plus, para mount plus"))
                    .accessibilityIdentifier("vocabulary.heardAs")
            }
            Text("Heard as is optional: separate spellings with commas. The term itself is always fixed whatever its letter case.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            if case .existing(let existing) = target {
                term = existing.term
                heardAs = existing.heardAs.joined(separator: ", ")
            }
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private func save() {
        let spellings = heardAs.split(separator: ",").map { String($0) }
        do {
            switch target {
            case .new: try store.add(term: term, heardAs: spellings)
            case .existing(let existing): try store.update(existing.id, term: term, heardAs: spellings)
            }
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// From a History row: teach Honyaku a word it got wrong. Past transcripts stay as they are.
struct AddToVocabularySheet: View {
    let transcript: String
    let store: VocabularyStore
    @Environment(\.dismiss) private var dismiss
    @State private var heardAs = ""
    @State private var writeAs = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add to vocabulary")
                .font(Theme.title)
            Text(transcript)
                .font(Theme.transcript)
                .lineSpacing(Theme.transcriptLineSpacing)
                .textSelection(.enabled)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: Theme.panelRadius))
            Form {
                TextField("Heard as", text: $heardAs, prompt: Text("plutotv"))
                TextField("Write it as", text: $writeAs, prompt: Text("Pluto TV"))
            }
            Text("Leave Heard as empty if only the letter case was wrong. This applies from your next dictation.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(writeAs.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func add() {
        do {
            try store.addFromHistory(heardAs: heardAs, writeAs: writeAs)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// History rows present "Add to vocabulary…" through this, so the row needs no vocabulary code of its own.
struct AddToVocabularyModifier: ViewModifier {
    let transcript: String
    @Binding var isPresented: Bool
    @Environment(FeatureEnvironment.self) private var features

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            AddToVocabularySheet(transcript: transcript, store: features.store(VocabularyStore.self))
        }
    }
}

extension View {
    func addToVocabularySheet(transcript: String, isPresented: Binding<Bool>) -> some View {
        modifier(AddToVocabularyModifier(transcript: transcript, isPresented: isPresented))
    }
}
