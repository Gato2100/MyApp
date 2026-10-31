import SwiftUI
import ImageIO

/// 全屏呈现的只读快照；ID 沿用文档身份，图片数据仅在当前解锁的界面会话中使用。
struct MemoImagePresentation: Identifiable {
    let id: UUID
    let data: Data
}

/// 文档详情使用的内存缩略图，避免列表/正文区域直接解码整张大图。
struct AttachmentThumbnail: View {
    let data: Data
    let open: () -> Void
    @State private var thumbnail: CGImage?
    @State private var failed = false
    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                if let thumbnail {
                    Image(uiImage: UIImage(cgImage: thumbnail)).resizable().scaledToFit()
                        .frame(maxWidth: 180, maxHeight: 150)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else if failed {
                    Label(L10n.text(.imageUnreadable), systemImage: "exclamationmark.triangle")
                } else {
                    ProgressView().frame(width: 120, height: 100)
                }
                Label(L10n.text(.viewFullImage), systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.text(.viewFullImage))
        // 在后台生成最长边 400 像素的方向修正缩略图；视图取消后不再发布结果。
        .task {
            let result = await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil as CGImage? }
                return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 400
                ] as CFDictionary)
            }.value
            guard !Task.isCancelled else { return }
            thumbnail = result; failed = result == nil
        }
    }
}

/// 全屏查看保存在文档中的完整图片；后台遮挡并退出，不能绕过根页面解锁流程。
struct AttachmentViewer: View {
    let data: Data
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        NavigationStack {
            ZoomableAttachment(data: data)
                .background(.black)
                .navigationTitle(L10n.text(.attachmentTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button(L10n.text(.closeImage)) { dismiss() } }
                }
                .safeAreaInset(edge: .bottom) {
                    Text(L10n.text(.imageZoomHelp)).font(.caption).foregroundStyle(.secondary).padding(8)
                }
        }
        .overlay {
            if scenePhase != .active {
                Color(.systemBackground).ignoresSafeArea().overlay { Label(L10n.text(.privacyCovered), systemImage: "lock.fill") }
            }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .background { dismiss() } }
    }
}

/// 借助 UIScrollView 实现稳定的缩放/拖动，图片只读且不导出到明文临时文件。
private struct ZoomableAttachment: UIViewRepresentable {
    let data: Data
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> AttachmentScrollView {
        let scroll = AttachmentScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 6
        scroll.backgroundColor = .black
        let view = context.coordinator.imageView
        view.image = UIImage(data: data)
        view.contentMode = .scaleAspectFit
        view.isAccessibilityElement = true
        view.accessibilityLabel = L10n.text(.attachmentTitle)
        view.frame = scroll.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.addSubview(view)
        scroll.zoomImageView = view
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(doubleTap)
        return scroll
    }
    func updateUIView(_ scroll: AttachmentScrollView, context: Context) {}
    /// 拆除 SwiftUI 桥接视图时主动释放 UIImage 与委托引用，缩短大图的内存占用。
    static func dismantleUIView(_ scroll: AttachmentScrollView, coordinator: Coordinator) {
        scroll.delegate = nil; coordinator.imageView.image = nil
    }
    /// 单独持有缩放内容视图；双击在适配全图与三倍缩放间切换。
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
        @objc func doubleTap(_ recognizer: UITapGestureRecognizer) {
            guard let scroll = recognizer.view as? UIScrollView else { return }
            if scroll.zoomScale > 1.1 { scroll.setZoomScale(1, animated: true) }
            else {
                let point = recognizer.location(in: imageView)
                let size = CGSize(width: scroll.bounds.width / 3, height: scroll.bounds.height / 3)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
            }
        }
    }
}

/// 首次获得有效布局或旋转改变尺寸时重新适配整图；普通拖动不重设缩放。
private final class AttachmentScrollView: UIScrollView {
    var zoomImageView: UIImageView?
    private var lastSize: CGSize = .zero
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.size != lastSize, bounds.width > 0, bounds.height > 0 else { return }
        lastSize = bounds.size
        setZoomScale(1, animated: false)
        zoomImageView?.frame = CGRect(origin: .zero, size: bounds.size)
        contentSize = bounds.size
    }
}
