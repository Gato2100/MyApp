import SwiftUI

struct ContentView: View {
    @State private var store = MemoStore()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if store.isUnlocked { MemoListView(store: store) }
            else { UnlockView(store: store) }
        }
        .overlay {
            if scenePhase != .active {
                Color(.systemBackground).ignoresSafeArea()
                    .overlay { Label(L10n.text(.privacyCovered), systemImage: "lock.fill") }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.lock() }
        }
    }
}

private struct UnlockView: View {
    let store: MemoStore
    @State private var password = ""
    @State private var confirmation = ""
    @State private var error: String?
    @ScaledMetric(relativeTo: .largeTitle) private var titleSize: CGFloat = 44
    private var actionTitle: String { L10n.text(store.exists ? .unlock : .createVault) }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 22) {
                    Text(L10n.text(.appName))
                        .font(.system(size: titleSize, weight: .semibold, design: .rounded))
                        .italic().tracking(1.2)
                        .foregroundStyle(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityAddTraits(.isHeader)

                    Image("LaunchArtwork")
                        .resizable().scaledToFit()
                        .frame(width: geometry.size.width * 0.75, height: geometry.size.width * 0.75)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .shadow(color: .blue.opacity(0.15), radius: 18, y: 8)
                        .accessibilityHidden(true)

                    VStack(spacing: 16) {
                        Text(L10n.text(store.exists ? .unlockHeading : .createHeading))
                            .font(.headline).multilineTextAlignment(.center)
                        SecureField(L10n.text(.password), text: $password)
                            .textContentType(store.exists ? .password : .newPassword)
                            .submitLabel(.go)
                            .accessibilityIdentifier("vault.password")
                            .modifier(VaultPasswordFieldStyle())
                        if !store.exists {
                            SecureField(L10n.text(.confirmPassword), text: $confirmation)
                                .textContentType(.newPassword).submitLabel(.go)
                                .accessibilityIdentifier("vault.confirmPassword")
                                .modifier(VaultPasswordFieldStyle())
                        }
                        VStack(spacing: 8) {
                            VaultActionButton(symbol: "lock.open.fill", title: actionTitle, isBusy: store.isBusy) { unlock() }
                                .disabled(store.isBusy || password.isEmpty || store.initializationError != nil)
                            Text(store.isBusy ? L10n.text(.verifying) : actionTitle)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text(L10n.text(store.exists ? .unlockHelp : .createHelp))
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if let message = error ?? store.initializationError {
                            Text(message).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                                .accessibilityIdentifier("vault.error")
                        }
                        if let notice = store.notice {
                            Text(notice).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: 420)
                    .padding(.horizontal, 24)
                    .disabled(store.isBusy)
                    .onSubmit { unlock() }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
        }
    }
    private func unlock() {
        guard !store.isBusy, !password.isEmpty else { return }
        if !store.exists {
            guard password.count >= 12 else { error = L10n.text(.passwordTooShort); return }
            guard password == confirmation else { error = L10n.text(.passwordMismatch); return }
        }
        error = nil
        let submittedPassword = password
        password = ""; confirmation = ""
        Task {
            do { try await store.unlock(password: submittedPassword) }
            catch { self.error = L10n.errorDescription(error) }
        }
    }
}

private enum MemoSheet: String, Identifiable {
    case text, photo
    var id: String { rawValue }
}

private struct MemoListView: View {
    let store: MemoStore
    @State private var query = ""
    @State private var searchScope = MemoSearchScope.all
    @State private var sheet: MemoSheet?
    @State private var selection = MemoSelection()
    @State private var pendingDeletion = Set<UUID>()
    @State private var confirmDeletion = false
    @State private var deletionError: String?
    private var results: [Memo] { Memo.search(store.memos, query: query, scope: searchScope) }
    private var visibleIDs: Set<UUID> { Set(results.map(\.id)) }

    var body: some View {
        NavigationStack {
            List(results) { memo in
                if selection.isSelecting {
                    Button { selection.toggle(memo.id) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: selection.ids.contains(memo.id) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(Color.accentColor)
                            MemoRow(memo: memo)
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(L10n.text(selection.ids.contains(memo.id) ? .tagSelected : .tagNotSelected))
                } else {
                    NavigationLink { MemoDetailView(store: store, id: memo.id) } label: { MemoRow(memo: memo) }
                }
            }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? L10n.text(.emptyMemos) : L10n.text(.noResults),
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(store.memos.isEmpty ? L10n.text(.emptyHelp) : L10n.text(.searchHelp)))
                }
            }
            .navigationTitle(selection.isSelecting ? L10n.format(.selectedMemoCount, selection.ids.count.formatted()) : L10n.text(.memos))
            .searchable(text: $query, prompt: Text(L10n.text(searchScope == .tags ? .tagSearchPrompt : .searchPrompt)))
            .searchScopes($searchScope) {
                Text(L10n.text(.searchAll)).tag(MemoSearchScope.all)
                Text(L10n.text(.searchTagsOnly)).tag(MemoSearchScope.tags)
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    if selection.isSelecting {
                        Button(role: .destructive) {
                            pendingDeletion = selection.ids.intersection(visibleIDs)
                            confirmDeletion = !pendingDeletion.isEmpty
                        } label: {
                            Label(L10n.format(.deleteSelectedMemos, selection.ids.count.formatted()), systemImage: "trash")
                        }.disabled(selection.ids.isEmpty)
                    } else {
                        Button { sheet = .photo } label: { Label(L10n.text(.photoMemoTitle), systemImage: "camera") }
                    }
                }
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarLeading) { leadingAction }
                        .sharedBackgroundVisibility(.hidden)
                } else {
                    ToolbarItem(placement: .topBarLeading) { leadingAction }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if selection.isSelecting {
                        Button(L10n.text(.finishSelection)) { selection.finish() }
                    } else {
                        Button(L10n.text(.selectMemos)) { selection.start() }.disabled(results.isEmpty)
                        Button { sheet = .text } label: { Label(L10n.text(.newText), systemImage: "square.and.pencil") }
                    }
                }
            }
            .sheet(item: $sheet) { destination in
                switch destination {
                case .text: MemoEditorView(store: store, original: Memo())
                case .photo: PhotoMemoView(store: store)
                }
            }
            .onChange(of: visibleIDs) { _, ids in selection.retainVisible(ids) }
            .onChange(of: query) { _, _ in selection.retainVisible(visibleIDs) }
            .onChange(of: searchScope) { _, _ in selection.retainVisible(visibleIDs) }
            .alert(L10n.text(.confirmDeleteMemos), isPresented: $confirmDeletion) {
                Button(L10n.text(.deleteMemos), role: .destructive) { deleteConfirmed() }
                Button(L10n.text(.cancel), role: .cancel) { pendingDeletion = [] }
            } message: {
                Text(L10n.format(.deleteMemosWarning, pendingDeletion.count.formatted()))
            }
            .alert(L10n.text(.deleteMemosFailed), isPresented: Binding(get: { deletionError != nil }, set: { if !$0 { deletionError = nil } })) {
                Button(L10n.text(.dismissDeleteError)) { deletionError = nil }
            } message: { Text(deletionError ?? "") }
        }
    }
    @ViewBuilder private var leadingAction: some View {
        if selection.isSelecting {
            Button(L10n.text(selection.ids == visibleIDs && !visibleIDs.isEmpty ? .deselectAllMemos : .selectAllMemos)) {
                selection.selectAll(visibleIDs)
            }.disabled(results.isEmpty)
        } else {
            VaultActionButton(symbol: "lock.fill", title: L10n.text(.lock)) { store.lock() }
        }
    }
    private func deleteConfirmed() {
        do {
            try store.delete(ids: pendingDeletion.intersection(visibleIDs))
            pendingDeletion = []; selection.finish()
        } catch {
            pendingDeletion = []; deletionError = L10n.errorDescription(error)
        }
    }
}

private struct MemoRow: View {
    let memo: Memo
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(memo.displayTitle).font(.headline).lineLimit(1)
            Text(memo.body).foregroundStyle(.secondary).lineLimit(2)
            if !memo.resolvedTags.isEmpty { TagBadges(tags: memo.resolvedTags) }
            HStack {
                Text(L10n.text(.updatedTime))
                Text(memo.updatedAt, format: .dateTime.year().month().day().hour().minute())
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MemoDetailView: View {
    let store: MemoStore
    let id: UUID
    @State private var editor: Memo?
    @State private var attachment: MemoImagePresentation?
    var body: some View {
        if let memo = store.memos.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(memo.displayTitle).font(.title.bold())
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent(L10n.text(.createdTime)) {
                            Text(memo.createdAt, format: .dateTime.year().month().day().hour().minute().second())
                        }
                        LabeledContent(L10n.text(.updatedTime)) {
                            Text(memo.updatedAt, format: .dateTime.year().month().day().hour().minute().second())
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                    Label((memo.source ?? .manual).label, systemImage: memo.source == .camera ? "camera" : memo.source == .photo ? "photo" : "pencil")
                        .font(.caption).foregroundStyle(.secondary)
                    if !memo.resolvedTags.isEmpty { TagBadges(tags: memo.resolvedTags) }
                    Text(memo.body).frame(maxWidth: .infinity, alignment: .leading)
                    if let data = memo.imageData {
                        Divider()
                        Text(L10n.text(.attachmentTitle)).font(.headline)
                        AttachmentThumbnail(data: data) { attachment = MemoImagePresentation(id: memo.id, data: data) }
                    }
                }.textSelection(.enabled).padding()
            }
            .navigationTitle(L10n.text(.memos)).navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(L10n.text(.edit)) { editor = memo } }
            .sheet(item: $editor) { MemoEditorView(store: store, original: $0) }
            .fullScreenCover(item: $attachment) { AttachmentViewer(data: $0.data) }
        }
    }
}

private struct MemoEditorView: View {
    let store: MemoStore
    let original: Memo
    @State private var tagDraft: TagDraft
    @State private var title: String
    @State private var text: String
    @State private var error: String?
    @State private var showDiscard = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    init(store: MemoStore, original: Memo) {
        self.store = store; self.original = original
        _tagDraft = State(initialValue: TagDraft(existing: original.resolvedTags, rejectedKeys: original.rejectedTagKeys ?? []))
        _title = State(initialValue: original.title); _text = State(initialValue: original.body)
    }
    private var changed: Bool { title != original.title || text != original.body || tagDraft.selected != original.resolvedTags || !tagDraft.pending.isEmpty || tagDraft.excluded != Set(original.rejectedTagKeys ?? []) }
    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                TextField(L10n.text(.titlePlaceholder), text: $title).font(.title2).accessibilityLabel(L10n.text(.titleAccessibility))
                Divider()
                Text(L10n.text(.body)).font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $text).frame(minHeight: 200, maxHeight: 300).accessibilityLabel(L10n.text(.body))
                TagEditorView(draft: tagDraft, input: TagInput(title: title, body: text))
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Text(L10n.text(.saveHelp))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            }
            .navigationTitle(store.memos.contains(where: { $0.id == original.id }) ? L10n.text(.editMemo) : L10n.text(.newMemo))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(.cancel)) { if changed { showDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text(.save)) { save() }.disabled(tagDraft.isGenerating || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(changed)
            .confirmationDialog(L10n.text(.discardQuestion), isPresented: $showDiscard, titleVisibility: .visible) {
                Button(L10n.text(.discard), role: .destructive) { dismiss() }
                Button(L10n.text(.keepEditing), role: .cancel) { }
            }
            .onChange(of: scenePhase) { _, phase in
                // Save synchronously on inactive before the root locks on background.
                if phase == .inactive, changed {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { save(close: false) }
                    else { store.notice = L10n.text(.emptyChangesNotice) }
                }
            }
        }
    }
    private func save(close: Bool = true) {
        guard tagDraft.commitPending() else {
            if !close { store.notice = L10n.text(.tagTooLong) }
            return
        }
        var memo = original
        memo.tags = tagDraft.selected(for: TagInput(title: title, body: text))
        memo.rejectedTagKeys = tagDraft.excluded.sorted()
        memo.title = title; memo.body = text
        do {
            try store.save(memo)
            if close { dismiss() }
        } catch {
            self.error = L10n.format(.saveFailed, L10n.errorDescription(error))
            if !close { store.notice = L10n.format(.backgroundSaveFailed, L10n.errorDescription(error)) }
        }
    }
}

private struct VaultPasswordFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.horizontal, 16).padding(.vertical, 15)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.blue.opacity(0.12), lineWidth: 1) }
    }
}
