import Foundation

/// 记录输入来源；枚举原始值属于持久化格式，不能随界面语言或文案调整。
enum MemoSource: String, Codable {
    case manual, camera, photo
    var label: String {
        switch self {
        case .manual: L10n.text(.sourceManual)
        case .camera: L10n.text(.sourceCamera)
        case .photo: L10n.text(.sourcePhoto)
        }
    }
}

/// 加密资料库中的文档值对象。UUID 用于稳定标识，时间戳用于追踪本地变更。
/// 可选扩展字段允许旧资料库缺少附件、标签等字段时继续解码。
struct Memo: Identifiable, Codable, Equatable {
    /// 创建草稿时分配，编辑与保存时沿用；不要用标题或数组位置代替文档身份。
    let id: UUID
    var title: String
    var body: String
    /// 两项时间保存绝对时刻；写权限限制在模型内部，由存储层调用统一规则维护。
    private(set) var createdAt: Date
    private(set) var updatedAt: Date
    var source: MemoSource?
    /// 保存 OCR 原始结果供后续核对，正文可以由用户单独修正。
    var originalRecognizedText: String?
    /// 图片与文字一起进入加密快照，不引用额外的明文附件路径。
    var imageData: Data?
    var tags: [String]?
    /// 记住用户取消的规范化标签，避免重新生成候选时又自动勾选。
    var rejectedTagKeys: [String]?
    /// 读取兼容视图：旧文档的 nil 视为空标签，并统一清洗及去重。
    var resolvedTags: [String] { TagRules.unique(tags ?? []) }
    /// 草稿时间仅是初始值；首次持久化时存储层会将两项时间重设为同一保存时刻。
    init(id: UUID = UUID(), title: String = "", body: String = "", createdAt: Date = .now, updatedAt: Date? = nil) {
        self.id = id; self.title = title; self.body = body
        self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
    }
    /// 只比较会持久化的内容；等价的空标签和拒选集合不应触发无意义的更新时间变化。
    func hasSameContent(as other: Memo) -> Bool {
        title == other.title && body == other.body && source == other.source &&
        originalRecognizedText == other.originalRecognizedText && imageData == other.imageData &&
        resolvedTags == other.resolvedTags && Set(rejectedTagKeys ?? []) == Set(other.rejectedTagKeys ?? [])
    }

    /// 保留既有创建时间，并在设备时钟回拨时仍推进同文档的本地更新时间。
    /// 这不等于跨设备冲突解决；远端导入需要独立合并规则。
    func preparingForLocalSave(previous: Memo?, at now: Date) -> Memo {
        var result = self
        if let previous {
            result.createdAt = previous.createdAt
            result.updatedAt = max(now, previous.updatedAt.addingTimeInterval(0.001), previous.createdAt)
        } else {
            result.createdAt = now
            result.updatedAt = now
        }
        return result
    }

    /// 空标题仅在显示时回退到正文首行；不把推导出的标题写回原始正文或标题字段。
    var displayTitle: String {
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return heading.isEmpty ? (body.split(whereSeparator: \.isNewline).first.map(String.init) ?? L10n.text(.untitled)) : heading
    }
    /// 多关键词按 AND 匹配；全部范围可跨标题、正文、标签命中，仅标签范围不读取正文。
    /// 标题命中优先，其后按更新时间倒序，最后以 UUID 保证同时间结果的稳定顺序。
    static func search(_ memos: [Memo], query: String, scope: MemoSearchScope = .all) -> [Memo] {
        let words = normalize(query).split(whereSeparator: \.isWhitespace).map(String.init)
        return memos.filter { memo in
            let tagText = memo.resolvedTags.joined(separator: "\n")
            let text = normalize(scope == .tags ? tagText : memo.title + "\n" + memo.body + "\n" + tagText)
            return words.allSatisfy { text.contains($0) }
        }.sorted { left, right in
            if !words.isEmpty && scope == .all {
                let a = words.allSatisfy { normalize(left.displayTitle).contains($0) }
                let b = words.allSatisfy { normalize(right.displayTitle).contains($0) }
                if a != b { return a }
            }
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.id.uuidString < right.id.uuidString
        }
    }
    /// 仅规范化搜索副本，保留用户原文；固定 locale 避免设备地区改变大小写折叠语义。
    private static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
