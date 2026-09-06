import Foundation

enum PersonalShared {
    static let group = "group.com.chaowu.audiobookshelf"
    static var groupsEnabled: Bool { Bundle.main.object(forInfoDictionaryKey: "PersonalAppGroupsEnabled") as? Bool ?? true }
    static var defaults: UserDefaults { groupsEnabled ? (UserDefaults(suiteName: group) ?? .standard) : .standard }
    static func directory() throws -> URL {
        let container = groupsEnabled ? FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) : FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let root = container else {
            throw NSError(domain: "PersonalImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "共享存储权限未启用"])
        }
        let inbox = root.appendingPathComponent("ImportInbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        return inbox
    }

    static func importFile(_ source: URL, suggestedName: String? = nil) throws {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        guard (try source.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else {
            throw NSError(domain: "PersonalImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "请分享音频文件，文件夹请在导入页选择"])
        }
        let id = UUID().uuidString
        let folder = try directory().appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let target = folder.appendingPathComponent("content")
            try FileManager.default.copyItem(at: source, to: target)
            let size = (try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
            var name = suggestedName?.isEmpty == false ? suggestedName! : source.lastPathComponent
            if URL(fileURLWithPath: name).pathExtension.isEmpty && !source.pathExtension.isEmpty { name += "." + source.pathExtension }
            let metadata: [String: Any] = ["id": id, "name": name, "size": size]
            try JSONSerialization.data(withJSONObject: metadata).write(to: folder.appendingPathComponent("info.json"), options: .atomic)
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }

    static func importFolder(id: String) throws -> URL {
        guard UUID(uuidString: id) != nil else { throw NSError(domain: "PersonalImport", code: 3, userInfo: [NSLocalizedDescriptionKey: "文件标识无效"]) }
        return try directory().appendingPathComponent(id, isDirectory: true)
    }

    static func imports() throws -> [[String: Any]] {
        let entries = try FileManager.default.contentsOfDirectory(at: directory(), includingPropertiesForKeys: nil)
        return entries.compactMap { folder in
            guard UUID(uuidString: folder.lastPathComponent) != nil,
                  let data = try? Data(contentsOf: folder.appendingPathComponent("info.json")),
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return value
        }.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
    }
}
