import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Settings > Vocabulary: the terms Honyaku always spells the user's way.
struct VocabularySettings: View {
    @Environment(FeatureEnvironment.self) private var features
    @State private var query = ""
    @State private var selection: VocabularyTerm.ID?
    @State private var editing: TermEditor.Target?
    @State private var alert: VocabularyAlert?

    private var store: VocabularyStore { features.store(VocabularyStore.self) }

    private var results: [VocabularyTerm] {
        let trimmed = VocabularyText.fold(query.trimmingCharacters(in: .whitespaces))
        guard !trimmed.isEmpty else { return store.terms }
        return store.terms.filter { term in
            ([term.term] + term.heardAs).contains { VocabularyText.fold($0).contains(trimmed) }
        }
    }

    /// The enabled terms likely to fit in the Whisper hint, from the top of the list.
    private var hintIDs: Set<VocabularyTerm.ID> {
        let enabled = store.enabledTerms
        return Set(enabled.prefix(WhisperHint.estimatedTermCount(enabled.map(\.term))).map(\.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let notice = store.corruptFileNotice {
                noticeBar(notice) { store.corruptFileNotice = nil }
            }
            if let notice = store.saveFailureNotice {
                noticeBar(notice) { store.saveFailureNotice = nil }
            }
            HStack {
                TextField("Search vocabulary", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button {
                    editing = .new
                } label: {
                    Label("Add term", systemImage: "plus")
                }
                .help("Add a term")
            }
            .padding(12)
            Divider()
            Group {
                if store.terms.isEmpty {
                    emptyState
                } else if results.isEmpty {
                    placeholder("Nothing matches \u{201C}\(query)\u{201D}.")
                } else {
                    termList
                }
            }
            .frame(maxHeight: .infinity)
            Divider()
            footer
        }
        .frame(width: 500, height: 440)
        .sheet(item: $editing) { target in
            TermEditor(target: target, store: store)
        }
        .alert(item: $alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
    }

    private var termList: some View {
        let hint = hintIDs
        let reorderable = query.trimmingCharacters(in: .whitespaces).isEmpty
        return List(selection: $selection) {
            ForEach(results) { term in
                TermRow(term: term, inHint: hint.contains(term.id), store: store,
                        onEdit: { editing = .existing(term) })
                    .tag(term.id)
            }
            // Dragging reorders the whole list, so it's only offered while every term is shown
            .onMove(perform: reorderable ? { store.move(fromOffsets: $0, toOffset: $1) } : nil)
        }
        .listStyle(.inset)
        .onDeleteCommand {
            if let selection { store.delete(selection) }
        }
        .contextMenu(forSelectionType: VocabularyTerm.ID.self) { ids in
            if let id = ids.first, let term = store.terms.first(where: { $0.id == id }) {
                Button("Edit\u{2026}") { editing = .existing(term) }
                Button("Move up") { store.move(id, by: -1) }
                    .disabled(store.terms.first?.id == id)
                Button("Move down") { store.move(id, by: 1) }
                    .disabled(store.terms.last?.id == id)
                Divider()
                Button("Delete", role: .destructive) { store.delete(id) }
            }
        } primaryAction: { ids in
            if let id = ids.first, let term = store.terms.first(where: { $0.id == id }) { editing = .existing(term) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("Add names, products and acronyms Honyaku should always spell your way.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add term") { editing = .new }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Honyaku writes these terms exactly as listed. With Whisper, terms marked \u{201C}In speech hint\u{201D} are also suggested to the speech model. The mark is an estimate: the exact cut is made when you dictate.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(store.terms.count) term\(store.terms.count == 1 ? "" : "s"), stored only on this Mac")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Import\u{2026}", action: importList)
                Button("Export\u{2026}", action: exportList)
                    .disabled(store.terms.isEmpty)
            }
        }
        .padding(12)
    }

    private func noticeBar(_ notice: String, dismiss: @escaping () -> Void) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                Label(notice, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Dismiss", action: dismiss)
            }
            .padding(12)
            Divider()
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
    }

    // MARK: - Import and export

    private func importList() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Honyaku word list to add to yours. Nothing in your list is removed."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            // Checked before reading, so a huge file is never loaded
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > VocabularyStore.importByteLimit {
                throw VocabularyImportError.tooLarge
            }
            let summary = try store.importData(Data(contentsOf: url))
            alert = VocabularyAlert(title: "Word list imported", message: summary.message + ".")
        } catch let error as VocabularyImportError {
            alert = VocabularyAlert(title: "Couldn\u{2019}t import", message: error.localizedDescription)
        } catch {
            alert = VocabularyAlert(title: "Couldn\u{2019}t import",
                                    message: "\u{201C}\(url.lastPathComponent)\u{201D} couldn\u{2019}t be read as a word list. Your list is unchanged.")
        }
    }

    private func exportList() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Honyaku Vocabulary.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportData().write(to: url, options: .atomic)
        } catch {
            alert = VocabularyAlert(title: "Couldn\u{2019}t export",
                                    message: "\(error.localizedDescription) Choose another folder and try again.")
        }
    }
}

private struct VocabularyAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

/// One term: on/off, how it's written, how it's misheard, and whether it's in the Whisper hint.
private struct TermRow: View {
    let term: VocabularyTerm
    let inHint: Bool
    let store: VocabularyStore
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Toggle("Use \(term.term)", isOn: Binding(get: { term.enabled },
                                                       set: { store.setEnabled(term.id, $0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(term.term)
                    .foregroundStyle(term.enabled ? .primary : .secondary)
                if !term.heardAs.isEmpty {
                    Text("Heard as \(term.heardAs.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if inHint {
                Label("In speech hint", systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(Theme.ai)
                    .accessibilityLabel("In speech hint, approximate")
            }
            HStack(spacing: 6) {
                Button(action: onEdit) { Image(systemName: "pencil") }
                    .help("Edit")
                    .accessibilityLabel("Edit \(term.term)")
                Button(role: .destructive) { store.delete(term.id) } label: { Image(systemName: "trash") }
                    .help("Delete")
                    .accessibilityLabel("Delete \(term.term)")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
