import SwiftUI
import ImageIO

struct MemoImagePresentation: Identifiable {
    let id: UUID
    let data: Data
}

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
    static func dismantleUIView(_ scroll: AttachmentScrollView, coordinator: Coordinator) {
        scroll.delegate = nil; coordinator.imageView.image = nil
    }
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
