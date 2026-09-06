import Foundation
import Capacitor
import WidgetKit

@objc(AbsPersonal)
public class AbsPersonal: CAPPlugin, CAPBridgedPlugin {
    public var identifier = "AbsPersonalPlugin"
    public var jsName = "AbsPersonal"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "listImports", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "readImportChunk", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "removeImports", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPlayback", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "takeAction", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "retrySync", returnType: CAPPluginReturnPromise)
    ]

    override public func load() {
        NotificationCenter.default.addObserver(self, selector: #selector(syncUpdated(_:)), name: Notification.Name("personal.progressSync"), object: nil)
    }
    @objc private func syncUpdated(_ notification: Notification) {
        notifyListeners("syncState", data: notification.userInfo as? [String: Any] ?? [:])
    }
    @objc func listImports(_ call: CAPPluginCall) {
        do { call.resolve(["files": try PersonalShared.imports()]) }
        catch { call.reject(error.localizedDescription) }
    }
    @objc func readImportChunk(_ call: CAPPluginCall) {
        guard let id = call.getString("id"), let offset = call.getInt("start"), let length = call.getInt("length"), offset >= 0, length >= 0, length <= 4 * 1024 * 1024 else { call.reject("读取范围无效"); return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let file = try PersonalShared.importFolder(id: id).appendingPathComponent("content")
                let handle = try FileHandle(forReadingFrom: file)
                defer { try? handle.close() }
                try handle.seek(toOffset: UInt64(offset))
                let data = try handle.read(upToCount: length) ?? Data()
                guard data.count == length else { throw NSError(domain: "PersonalImport", code: 4, userInfo: [NSLocalizedDescriptionKey: "共享文件不完整，请重新分享"]) }
                call.resolve(["data": data.base64EncodedString()])
            } catch { call.reject(error.localizedDescription) }
        }
    }
    @objc func removeImports(_ call: CAPPluginCall) {
        do { for id in call.getArray("ids", String.self) ?? [] { try FileManager.default.removeItem(at: PersonalShared.importFolder(id: id)) }; call.resolve() }
        catch { call.reject(error.localizedDescription) }
    }
    @objc func getPlayback(_ call: CAPPluginCall) {
        let value = PersonalShared.defaults.dictionary(forKey: "playback") ?? [:]
        call.resolve(["playback": value, "syncState": UserDefaults.standard.string(forKey: "personal.syncState") ?? "synced"])
    }
    @objc func takeAction(_ call: CAPPluginCall) {
        let value = PersonalShared.defaults.string(forKey: "pendingAction") ?? ""
        PersonalShared.defaults.removeObject(forKey: "pendingAction")
        call.resolve(["action": value])
    }
    @objc func retrySync(_ call: CAPPluginCall) { Task { await PlayerProgress.shared.retryPending(); call.resolve() } }
}

enum PersonalPlayback {
    private static var lastWrite: Double = 0
    static func remember(session: PlaybackSession) {
        let playableId = session.localLibraryItem?.id ?? session.libraryItemId ?? ""
        PersonalShared.defaults.set(["id": playableId, "episodeId": session.episodeId ?? "", "title": session.displayTitle ?? "正在听", "author": session.displayAuthor ?? "", "position": session.currentTime, "duration": session.duration, "serverId": session.serverConnectionConfigId ?? ""], forKey: "playback")
        lastWrite = 0
        WidgetCenter.shared.reloadTimelines(ofKind: "ContinueListening")
    }
    static func update(position: Double, duration: Double, chapter: String?) {
        let now = Date().timeIntervalSince1970
        guard now - lastWrite >= 30 else { return }
        lastWrite = now
        guard var value = PersonalShared.defaults.dictionary(forKey: "playback") else { return }
        value["position"] = position; value["duration"] = duration; value["chapter"] = chapter ?? ""
        PersonalShared.defaults.set(value, forKey: "playback")
        WidgetCenter.shared.reloadTimelines(ofKind: "ContinueListening")
    }
    static func resume(id: String? = nil, completion: @escaping (Bool) -> Void = { _ in }) {
        let value = PersonalShared.defaults.dictionary(forKey: "playback") ?? [:]
        guard let selected = id ?? value["id"] as? String else { completion(false); return }
        guard selected.hasPrefix("local_") || value["serverId"] as? String == Store.serverConfig?.id else { completion(false); return }
        let episodeId = selected == value["id"] as? String ? (value["episodeId"] as? String).flatMap { $0.isEmpty ? nil : $0 } : nil
        let rate = PlayerSettings.main().playbackRate
        let start: (PlaybackSession) -> Void = { session in
            guard session.libraryItemId != nil, !session.id.isEmpty else { completion(false); return }
            do {
                PlayerHandler.stopPlayback()
                try session.save()
                if let plugin = AbsAudioPlayer.instance { try plugin.startPlaybackSession(session, playWhenReady: true, playbackRate: rate) }
                else { PlayerHandler.startPlayback(sessionId: session.id, playWhenReady: true, playbackRate: rate) }
                completion(true)
            } catch { AbsLogger.error(message: "无法继续播放", error: error); completion(false) }
        }
        if selected.hasPrefix("local_"), let item = Database.shared.getLocalLibraryItem(localLibraryItemId: selected) {
            start(item.getPlaybackSession(episode: item.getPodcastEpisode(episodeId: episodeId)))
        } else { ApiClient.startPlaybackSession(libraryItemId: selected, episodeId: episodeId, forceTranscode: false, callback: start) }
    }
}
