import Foundation

/// 搜索范围与界面翻译无关；默认同时搜索文档内容和标签。
enum MemoSearchScope: String, CaseIterable { case all, tags }

/// 标题和正文的不可变快照，用作防抖任务身份，避免异步结果套用到其他内容。
struct TagInput: Equatable {
    let title: String
    let body: String
    var document: String { title + "\n" + body }
}

/// 标签输入、模型输出和搜索共用的规范化规则，确保同一个标签不会以等价形式重复。
enum TagRules {
    // AI 候选严格少于 4 个；不限制用户最终手动追加的标签数量。
    static let maximumSuggestions = 3
    static let maximumLength = 32
    /// 清理展示值，去掉前导井号并归一化空白，不把逗号或空格自动拆成多个标签。
    static func clean(_ tag: String) -> String {
        var result = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        while result.hasPrefix("#") || result.hasPrefix("＃") { result.removeFirst() }
        return result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    /// 等价判定使用固定 locale 的大小写/全半角折叠；展示仍保留首次输入的写法。
    static func key(_ tag: String) -> String {
        clean(tag).precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
    /// 保留首次出现顺序，过滤空值及超长标签；人工输入会先在编辑器给出长度错误。
    static func unique(_ tags: [String]) -> [String] {
        var keys = Set<String>()
        return tags.map(clean).filter { !$0.isEmpty && $0.count <= maximumLength && keys.insert(key($0)).inserted }
    }
}
