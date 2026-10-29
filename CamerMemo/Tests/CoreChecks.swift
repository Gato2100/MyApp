import Foundation

@main
struct CoreChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vault = EncryptedVault(url: directory.appendingPathComponent("vault.cmemo"))
        let password = "test-长口令-123456789"
        let session = try vault.create(password: password)
        var memo = Memo(title: "新宿 ＣＡＭＥＲＡ", body: "周五购买索尼镜头，预算十万日元。\n二行目：写真")
        let attachment = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/l9sAAAAASUVORK5CYII=")!
        memo.tags = ["旅行", "Ｔｏｋｙｏ"]
        memo.rejectedTagKeys = ["购物"]
        memo.imageData = attachment
        memo.source = .camera
        memo.originalRecognizedText = "原始识别文字"
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(memo)) as! [String: Any]
        legacy.removeValue(forKey: "tags"); legacy.removeValue(forKey: "rejectedTagKeys"); legacy.removeValue(forKey: "imageData"); legacy.removeValue(forKey: "source"); legacy.removeValue(forKey: "originalRecognizedText")
        let oldMemo = try JSONDecoder().decode(Memo.self, from: JSONSerialization.data(withJSONObject: legacy))
        assert(oldMemo.tags == nil && oldMemo.rejectedTagKeys == nil && oldMemo.imageData == nil && oldMemo.source == nil && oldMemo.body == memo.body)
        try vault.save([memo], session: session)
        let restored = try vault.open(password: password).1
        assert(restored == [memo])
        assert(restored.first?.imageData == attachment)
        assert(restored.first?.tags == memo.tags && restored.first?.rejectedTagKeys == memo.rejectedTagKeys)
        let original = try Data(contentsOf: vault.url)
        assert(!String(decoding: original, as: UTF8.self).contains("索尼镜头"))
        assert(!String(decoding: original, as: UTF8.self).contains("旅行"))
        assert(!String(decoding: original, as: UTF8.self).contains(attachment.base64EncodedString()))
        assert(Memo.search([memo], query: "旅行").count == 1)
        assert(Memo.search([memo], query: "TOKYO", scope: .tags).count == 1)
        assert(Memo.search([memo], query: "旅行 tokyo", scope: .tags).count == 1)
        assert(Memo.search([memo], query: "新宿", scope: .tags).isEmpty)
        assert(Memo.search([memo], query: "旅行 镜头").count == 1)
        assert(Memo.search([memo], query: "旅行 镜头", scope: .tags).isEmpty)
        assert(Memo.search([memo], query: "新").count == 1)
        assert(Memo.search([memo], query: "写真").count == 1)
        assert(Memo.search([memo], query: "camera 镜头").count == 1)
        assert(Memo.search([memo], query: "camera 不存在").isEmpty)
        assert(Memo.search([memo], query: "  \n ").count == 1)
        assert(Memo.search([memo], query: "' OR 1=1 %_").isEmpty)
        assert(Memo(title: " ", body: "第一行\n第二行").displayTitle == "第一行")
        do { _ = try vault.open(password: "wrong"); fatalError("Wrong password accepted") } catch {}
        let afterWrongPassword = try Data(contentsOf: vault.url)
        assert(afterWrongPassword == original)
        var edited = memo
        edited.body = "编辑后的正文"
        edited = edited.preparingForLocalSave(previous: memo, at: .now)
        try vault.save([edited], session: session)
        let restoredEdit = try vault.open(password: password).1
        assert(restoredEdit == [edited])
        assert(restoredEdit.first?.imageData == attachment)
        assert(Memo.search([edited], query: "索尼").isEmpty)
        assert(Memo.search([edited], query: "编辑后").count == 1)
        let fresh = try Data(contentsOf: vault.url)
        try vault.save([edited], session: session)
        let resealed = try Data(contentsOf: vault.url)
        assert(resealed != fresh, "Each encryption must use a new nonce")
        do { _ = try vault.create(password: password); fatalError("Existing vault overwritten") } catch {}
        var json = try JSONSerialization.jsonObject(with: fresh) as! [String: Any]
        var payload = Data(base64Encoded: json["payload"] as! String)!
        payload[payload.startIndex + 15] ^= 1
        json["payload"] = payload.base64EncodedString()
        try JSONSerialization.data(withJSONObject: json).write(to: vault.url)
        do { _ = try vault.open(password: password); fatalError("Tampering accepted") } catch {}
        try Data(fresh.prefix(30)).write(to: vault.url)
        do { _ = try vault.open(password: password); fatalError("Truncation accepted") } catch {}
        print("PASS: encrypted tags/attachments roundtrip, combined and tags-only search, attachment retained after edits, legacy compatibility, search, Unicode/width/case, AND terms, wrong password, fresh nonce, tampering, truncation, no overwrite")
    }
}
