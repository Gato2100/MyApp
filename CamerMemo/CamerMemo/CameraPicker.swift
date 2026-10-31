import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 把系统相机桥接到 SwiftUI；权限与相机可用性由呈现它的 PhotoMemoView 预先检查。
/// 只回传内存图片，不主动保存到系统相册。
struct CameraPicker: UIViewControllerRepresentable {
    let completion: (UIImage?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    /// 仅开启静态照片拍摄，避免返回视频后误走文字识别流程。
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.mediaTypes = [UTType.image.identifier]
        controller.cameraCaptureMode = .photo
        controller.delegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    /// 将 UIKit 的完成/取消事件转换为单一回调，关闭呈现由外层状态管理。
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (UIImage?) -> Void
        init(completion: @escaping (UIImage?) -> Void) { self.completion = completion }
        /// nil 表示用户取消，不应创建文档或显示识别失败。
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(nil) }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            completion(info[.originalImage] as? UIImage)
        }
    }
}
