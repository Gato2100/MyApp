import SwiftUI
import PhotosUI
import AVFoundation

/// 图片导入会话：拍照/选图 → 内存预览与 OCR → 人工校对及标签选择 → 加密保存。
/// 在用户保存前不写入图片文档；真正进入后台时清除未保存的导入内容。
struct PhotoMemoView: View {
    let store: MemoStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: PhotosPickerItem?
    @State private var showCamera = false
    @State private var requestCamera = false
    @State private var pendingCameraImage: UIImage?
    // 待识别文件与持久化附件分开：OCR 可以缩小图片，但附件保留完整文件数据。
    @State private var incomingData: Data?
    @State private var image: CGImage?
    @State private var attachmentData: Data?
    // 任务 ID 既用于驱动 .task 取消，也用于阻止旧图片的识别结果覆盖新图片。
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
    /// 汇总各阶段忙碌状态，防止读取、拍摄转换和识别期间再次修改输入。
    private var working: Bool { busy || loadingPhoto || preparingCamera || requestCamera }
    /// 即使用户清空识别正文，也保留校对界面及放弃确认，直到明确重选或退出。
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
            // 系统相机需要全屏呈现；等待关闭动画完成后再转换拍摄图片。
            .fullScreenCover(isPresented: $showCamera, onDismiss: {
                if pendingCameraImage != nil { cameraConversionID = UUID() }
            }) {
                CameraPicker { image in
                    pendingCameraImage = image
                    showCamera = false
                }.ignoresSafeArea()
            }
            // 权限弹窗可能使场景短暂 inactive；只在真正 background 时让根视图锁定。
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
            // PhotosPicker 只传回所选照片；云端照片可能需系统下载，取消后不应用读取结果。
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
            // 拍摄图按完整尺寸归一化方向并编码为 JPEG；识别副本在服务层另行缩小。
            .task(id: cameraConversionID) {
                guard let captured = pendingCameraImage else { return }
                pendingCameraImage = nil
                incomingData = nil; image = nil; attachmentData = nil
                preparingCamera = true
                defer { preparingCamera = false }
                let size = captured.size
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let normalized = UIGraphicsImageRenderer(size: size, format: format).image { _ in captured.draw(in: CGRect(origin: .zero, size: size)) }
                guard !Task.isCancelled, store.isUnlocked else { return }
                guard let data = normalized.jpegData(compressionQuality: 0.9) else { message = L10n.text(.imageUnreadable); return }
                source = .camera; incomingData = data; workID = UUID()
            }
            // 图片/任务变化会取消旧流程；每次异步等待后都需重新验证会话是否仍解锁。
            .task(id: workID) {
                guard let workID, let data = incomingData else { return }
                busy = true; message = nil
                defer { if self.workID == workID { busy = false } }
                do {
                    let prepared = try await TextRecognitionService.prepare(data)
                    guard !Task.isCancelled, store.isUnlocked else { return }
                    image = prepared
                    // 在 OCR 前保留可读取附件，无文字时仍可转为手动填写并保存该图片。
                    attachmentData = data
                    let result = try await TextRecognitionService.recognize(prepared, language: language)
                    try Task.checkCancellation()
                    guard store.isUnlocked, self.workID == workID else { return }
                    // 识别原文与可编辑正文分开保存，后续校对不会改写原始识别结果。
                    originalText = result; text = result
                    incomingData = nil
                } catch {
                    if !Task.isCancelled, store.isUnlocked { message = L10n.errorDescription(error) }
                }
            }
            // 当前尚无图片草稿恢复；后台清理必须同时清理文字、标签、图片和未完成任务。
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
    /// 通过改变 .task 的驱动 ID 触发取消，不把用户主动停止当作识别错误。
    private func cancelWork() {
        workID = nil; selection = nil; requestCamera = false; cameraConversionID = nil
        busy = false; loadingPhoto = false; preparingCamera = false
    }
    /// 明确放弃当前图片时清理整个导入会话，避免旧图、旧标签或错误提示混入新文档。
    private func reset() {
        tagDraft.reset()
        cancelWork(); incomingData = nil; image = nil; attachmentData = nil; pendingCameraImage = nil
        text = ""; title = ""; originalText = nil; message = nil; cameraDenied = false
    }
    /// 只有有效正文与完整附件同时存在才提交；时间戳由 MemoStore 统一生成。
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
