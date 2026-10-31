import Foundation

/// 纯值类型选择状态，不负责持久化；切换搜索结果时由列表传入当前可见 ID。
struct MemoSelection {
    private(set) var isSelecting = false
    private(set) var ids = Set<UUID>()
    /// 开始或结束多选均清空旧选择，避免前一次操作的选择被复用。
    mutating func start() { isSelecting = true; ids = [] }
    mutating func finish() { isSelecting = false; ids = [] }
    /// 非选择模式下忽略行选择，保持普通点击仍用于打开详情。
    mutating func toggle(_ id: UUID) {
        guard isSelecting else { return }
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
    }
    /// 全选仅覆盖可见结果；已全部选中时切换为取消全选。
    mutating func selectAll(_ visible: Set<UUID>) { ids = ids == visible ? [] : visible }
    /// 查询或搜索范围改变后移除隐藏选择，防止确认数量与用户看到的项目不一致。
    mutating func retainVisible(_ visible: Set<UUID>) { ids.formIntersection(visible) }
}
