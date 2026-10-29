import Foundation

enum MemoSearchScope: String, CaseIterable { case all, tags }

struct TagInput: Equatable {
    let title: String
    let body: String
    var document: String { title + "\n" + body }
}

enum TagRules {
    static let maximumSuggestions = 3
    static let maximumLength = 32
    static func clean(_ tag: String) -> String {
        var result = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasPrefix("#") || result.hasPrefix("＃") { result.removeFirst() }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    static func key(_ tag: String) -> String {
        clean(tag).precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    static func unique(_ tags: [String]) -> [String] {
        var keys = Set<String>()
        return tags.map(clean).filter { !$0.isEmpty && $0.count <= maximumLength && keys.insert(key($0)).inserted }
    }
}
