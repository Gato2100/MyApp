import SwiftUI

struct TagEditorView: View {
    @Bindable var draft: TagDraft
    let input: TagInput
    @State private var retry = 0
    @State private var paused = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.text(.tagsTitle)).font(.headline)
            if !draft.manual.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], alignment: .leading) {
                    ForEach(draft.manual, id: \.self) { tag in
                        Button { draft.remove(tag) } label: {
                            HStack { Text(tag).lineLimit(2); Image(systemName: "xmark.circle") }.font(.caption)
                        }.buttonStyle(.bordered).accessibilityLabel(L10n.format(.removeTag, tag))
                    }
                }
            }
            HStack {
                TextField(L10n.text(.tagInputPlaceholder), text: $draft.pending)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .onSubmit { draft.commitPending() }
                Button(L10n.text(.addTag)) { draft.commitPending() }
                    .disabled(TagRules.clean(draft.pending).isEmpty)
            }
            if let error = draft.inputError { Text(error).font(.caption).foregroundStyle(.red) }
            Text(L10n.text(.tagSuggestionHelp)).font(.caption).foregroundStyle(.secondary)
            if draft.isGenerating {
                ProgressView(L10n.text(.tagGenerating))
                Button(L10n.text(.cancelTagGeneration)) { paused = true }.font(.caption)
            }
            ForEach(draft.suggestions.filter { suggestion in !draft.manual.contains { TagRules.key($0) == TagRules.key(suggestion) } }, id: \.self) { tag in
                Button { draft.toggle(tag) } label: {
                    Label(tag, systemImage: draft.isSelected(tag) ? "checkmark.circle.fill" : "circle")
                }
                .buttonStyle(.plain)
                .accessibilityValue(L10n.text(draft.isSelected(tag) ? .tagSelected : .tagNotSelected))
            }
            if let message = draft.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            Button(L10n.text(.regenerateTags)) { paused = false; retry += 1 }
                .font(.caption).disabled(draft.isGenerating || input.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .buttonStyle(.borderless)
        .task(id: RefreshID(input: input, retry: retry, paused: paused)) {
            draft.prepare(for: input)
            guard !paused else { draft.cancel(); return }
            guard !input.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            await draft.generate(for: input)
        }
        .onDisappear { draft.cancel() }
    }
    private struct RefreshID: Equatable { let input: TagInput; let retry: Int; let paused: Bool }
}

struct TagBadges: View {
    let tags: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading, spacing: 6) {
            ForEach(TagRules.unique(tags), id: \.self) { tag in
                Text(tag).font(.caption).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.tint.opacity(0.12), in: Capsule())
            }
        }
    }
}
