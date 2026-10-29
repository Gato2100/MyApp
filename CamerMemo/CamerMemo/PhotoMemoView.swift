import SwiftUI
import PhotosUI
import AVFoundation

struct PhotoMemoView: View {
    let store: MemoStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: PhotosPickerItem?
    @State private var showCamera = false
    @State private var requestCamera = false
    @State private var pendingCameraImage: UIImage?
    @State private var incomingData: Data?
    @State private var image: CGImage?
    @State private var attachmentData: Data?
    @State private var workID: UUID?
    @State private var cameraConversionID: UUID?
    @State private var busy = false
    @State private var loadingPhoto = false
    @State private var preparingCamera = false
    @State private var language = RecognitionLanguage.automatic
    @State private var title = ""
    @State private var tagDraft = TagDraft()
    @State private var text = ""
    @State private var originalText: String?
    @State private var source = MemoSource.photo
    @State private var message: String?
    @State private var cameraDenied = false
    @State private var showDiscard = false
    @State private var resetAfterDiscard = false
    private var working: Bool { busy || loadingPhoto || preparingCamera || requestCamera }
    private var hasReview: Bool { originalText != nil || !text.isEmpty || !title.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(L10n.text(.photoPrivacyHelp)).font(.footnote).foregroundStyle(.secondary)
                    if !hasReview {
                        Button { requestCamera = true } label: { Label(L10n.text(.takePhoto), systemImage: "camera") }
                            .disabled(working)
                        PhotosPicker(selection: $selection, matching: .images, preferredItemEncoding: .current) {
                            Label(L10n.text(.choosePhoto), systemImage: "photo.on.rectangle")
                        }.disabled(working)
                    } else {
                        Button(L10n.text(.chooseAnotherPhoto)) { resetAfterDiscard = true; showDiscard = true }
                    }
                    Picker(L10n.text(.recognitionLanguage), selection: $language) {
                        ForEach(RecognitionLanguage.allCases) { Text($0.label).tag($0) }
                    }.disabled(working || hasReview)
                }
                if let image {
                    Section {
                        Image(decorative: image, scale: 1).resizable().scaledToFit().frame(maxHeight: 240)
                            .accessibilityLabel(L10n.text(.selectedPhoto))
                    }
                }
                if working {
                    Section {
                        ProgressView(L10n.text(busy ? .recognizingText : .loadingPhoto))
                        Button(L10n.text(.cancelRecognition)) { cancelWork() }
                    }
                }
                if let message {
                    Section {
                        Text(message).foregroundStyle(.red)
                        if cameraDenied {
                            Button(L10n.text(.openSettings)) {
                                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                            }
                        }
                    }
                }
                if incomingData != nil && !working && !hasReview {
                    Section {
                        Button(L10n.text(.retryRecognition)) { message = nil; workID = UUID() }
                        if attachmentData != nil {
                            Button(L10n.text(.enterPhotoTextManually)) { originalText = ""; message = nil }
                        }
                    }
                }
                if hasReview {
                    Section(L10n.text(.reviewRecognizedText)) {
                        Text(L10n.text(.reviewHelp)).font(.footnote).foregroundStyle(.secondary)
                        TextField(L10n.text(.titlePlaceholder), text: $title).accessibilityLabel(L10n.text(.titleAccessibility))
                        TextEditor(text: $text).frame(minHeight: 220).accessibilityLabel(L10n.text(.body))
                    }
                    Section { TagEditorView(draft: tagDraft, input: TagInput(title: title, body: text)) }
                }
            }
            .navigationTitle(L10n.text(.photoMemoTitle)).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(.cancel)) {
                        if hasReview { resetAfterDiscard = false; showDiscard = true }
                        else { cancelWork(); dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.text(.save)) { save() }
                        .disabled(working || tagDraft.isGenerating || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(hasReview || working)
            .confirmationDialog(L10n.text(.discardQuestion), isPresented: $showDiscard, titleVisibility: .visible) {
                Button(L10n.text(.discard), role: .destructive) {
                    if resetAfterDiscard { reset() } else { cancelWork(); dismiss() }
                }
                Button(L10n.text(.keepEditing), role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                if pendingCameraImage != nil { cameraConversionID = UUID() }
            }) {
                CameraPicker { image in
                    pendingCameraImage = image
                    showCamera = false
                }.ignoresSafeArea()
            }
            .task(id: requestCamera) {
                guard requestCamera else { return }
                defer { requestCamera = false }
                message = nil; cameraDenied = false
                guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                    message = L10n.text(.cameraUnavailable); return
                }
                let authorized: Bool
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized: authorized = true
                case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
                default: authorized = false
                }
                guard !Task.isCancelled, store.isUnlocked else { return }
                if authorized { showCamera = true }
                else { cameraDenied = true; message = L10n.text(.cameraDenied) }
            }
            .task(id: selection) {
                guard let selection else { return }
                loadingPhoto = true; message = nil; cameraDenied = false
                incomingData = nil; image = nil; attachmentData = nil
                defer { loadingPhoto = false }
                do {
                    guard let data = try await selection.loadTransferable(type: Data.self) else { throw PhotoImportError.imageUnreadable }
                    try Task.checkCancellation()
                    guard store.isUnlocked else { return }
                    source = .photo; incomingData = data; workID = UUID()
                } catch {
                    if !Task.isCancelled { message = L10n.text(.imageUnreadable) }
                }
                self.selection = nil
            }
            .task(id: cameraConversionID) {
                guard let captured = pendingCameraImage else { return }
                pendingCameraImage = nil
                incomingData = nil; image = nil; attachmentData = nil
                preparingCamera = true
                defer { preparingCamera = false }
                // Preserve full camera dimensions and normalize orientation. OCR downsamples separately.
                let size = captured.size
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in captured.draw(in: CGRect(origin: .zero, size: size)) }
                guard !Task.isCancelled, store.isUnlocked else { return }
                guard let data = normalized.jpegData(compressionQuality: 0.9) else { message = L10n.text(.imageUnreadable); return }
                source = .camera; incomingData = data; workID = UUID()
            }
            .task(id: workID) {
                guard let workID, let data = incomingData else { return }
                busy = true; message = nil
                defer { if self.workID == workID { busy = false } }
                do {
                    let prepared = try await TextRecognitionService.prepare(data)
                    guard !Task.isCancelled, store.isUnlocked else { return }
                    image = prepared
                    attachmentData = data
                    let result = try await TextRecognitionService.recognize(prepared, language: language)
                    try Task.checkCancellation()
                    guard store.isUnlocked, self.workID == workID else { return }
                    originalText = result; text = result
                    incomingData = nil
                } catch {
                    if !Task.isCancelled, store.isUnlocked { message = L10n.errorDescription(error) }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    if hasReview { store.notice = L10n.text(.photoReviewNotSaved) }
                    tagDraft.reset()
                    cancelWork(); incomingData = nil; image = nil; attachmentData = nil; pendingCameraImage = nil
                    text = ""; title = ""; originalText = nil
                }
            }
            .onDisappear { cancelWork() }
        }
    }
    private func cancelWork() {
        workID = nil; selection = nil; requestCamera = false; cameraConversionID = nil
        busy = false; loadingPhoto = false; preparingCamera = false
    }
    private func reset() {
        tagDraft.reset()
        cancelWork(); incomingData = nil; image = nil; attachmentData = nil; pendingCameraImage = nil
        text = ""; title = ""; originalText = nil; message = nil; cameraDenied = false
    }
    private func save() {
        guard tagDraft.commitPending() else { return }
        var memo = Memo(title: title, body: text)
        memo.source = source; memo.originalRecognizedText = originalText
        guard let attachmentData else { message = L10n.text(.imageUnreadable); return }
        memo.imageData = attachmentData
        memo.tags = tagDraft.selected(for: TagInput(title: title, body: text))
        memo.rejectedTagKeys = tagDraft.excluded.sorted()
        do { try store.save(memo); dismiss() }
        catch { message = L10n.format(.saveFailed, L10n.errorDescription(error)) }
    }
}
