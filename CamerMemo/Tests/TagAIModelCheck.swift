import Foundation

/// 可选的真实设备端模型检查；模型不可用时明确跳过，不能把跳过当成生成成功。
@main
struct TagAIModelCheck {
    static func main() async throws {
        if let unavailable = TagGenerationService.unavailableMessage {
            print("SKIP: on-device AI unavailable: \(unavailable)")
            return
        }
        let tags = try await TagGenerationService.suggest(for: TagInput(title: "镜头购物", body: "周五去新宿的相机店购买索尼镜头，预算十万日元。"))
        precondition(tags.count <= 3 && tags.allSatisfy { !$0.isEmpty && $0.count <= 32 })
        print("PASS: actual on-device AI returned \(tags.count) tags: \(tags)")
    }
}
