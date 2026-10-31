import SwiftUI

/// 应用唯一入口：会话状态由根视图持有，不在启动时读取或解密备忘录。
@main
struct CamerMemoApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
