import Foundation

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

struct Memo: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var body: String
    private(set) var createdAt: Date
    private(set) var updatedAt: Date
    var source: MemoSource?
    var originalRecognizedText: String?
    var imageData: Data?
    var tags: [String]?
    var rejectedTagKeys: [String]?
    var resolvedTags: [String] { TagRules.unique(tags ?? []) }
    init(id: UUID = UUID(), title: String = "", body: String = "", createdAt: Date = .now, updatedAt: Date? = nil) {
        self.id = id; self.title = title; self.body = body
        self.createdAt = createdAt; self.updatedAt = updatedAt ?? createdAt
    }
    /// Compare persisted user content, ignoring timestamps and equivalent empty/normalized tags.
    func hasSameContent(as other: Memo) -> Bool {
        title == other.title && body == other.body && source == other.source &&
        originalRecognizedText == other.originalRecognizedText && imageData == other.imageData &&
        resolvedTags == other.resolvedTags && Set(rejectedTagKeys ?? []) == Set(other.rejectedTagKeys ?? [])
    }

    /// Called by local persistence only. Future remote imports need separate merge semantics.
    func preparingForLocalSave(previous: Memo?, at now: Date) -> Memo {
        var result = self
        if let previous {
            result.createdAt = previous.createdAt
            // Ensure a local edit advances even if the wall clock moves backwards.
            result.updatedAt = max(now, previous.updatedAt.addingTimeInterval(0.001), previous.createdAt)
        } else {
            result.createdAt = now
            result.updatedAt = now
        }
        return result
    }

    var displayTitle: String {
        let heading = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return heading.isEmpty ? (body.split(whereSeparator: \.isNewline).first.map(String.init) ?? L10n.text(.untitled)) : heading
    }
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
    private static func normalize(_ text: String) -> String {
        text.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
