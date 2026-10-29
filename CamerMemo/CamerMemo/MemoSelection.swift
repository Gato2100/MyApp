import Foundation

/// Selection is always constrained to the currently visible search results.
struct MemoSelection {
    private(set) var isSelecting = false
    private(set) var ids = Set<UUID>()
    mutating func start() { isSelecting = true; ids = [] }
    mutating func finish() { isSelecting = false; ids = [] }
    mutating func toggle(_ id: UUID) {
        guard isSelecting else { return }
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
    }
    mutating func selectAll(_ visible: Set<UUID>) { ids = ids == visible ? [] : visible }
    mutating func retainVisible(_ visible: Set<UUID>) { ids.formIntersection(visible) }
}
