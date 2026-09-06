import CarPlay
import RealmSwift

/// Activate only in a profile granted com.apple.developer.carplay-audio by Apple.
class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private var controller: CPInterfaceController?
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didConnect interfaceController: CPInterfaceController) {
        controller = interfaceController
        var sections = [CPListSection]()
        let value = PersonalShared.defaults.dictionary(forKey: "playback") ?? [:]
        if let id = value["id"] as? String {
            sections.append(CPListSection(items: [entry(id: id, title: value["title"] as? String ?? "上次的书", detail: "继续听")]))
        }
        if let realm = try? Realm() {
            let downloaded = realm.objects(LocalLibraryItem.self).filter { $0.isBook }.prefix(60).map { item in
                self.entry(id: item.id, title: item.media?.metadata?.title ?? "有声书", detail: "已下载，可离线播放")
            }
            if !downloaded.isEmpty { sections.append(CPListSection(items: Array(downloaded), header: "已下载", sectionIndexTitle: nil)) }
        }
        if sections.isEmpty { sections = [CPListSection(items: [CPListItem(text: "先在 iPhone 添加一本书", detailText: "打开 Audiobookshelf，选择书籍后即可在这里继续听。")])] }
        interfaceController.setRootTemplate(CPListTemplate(title: "Audiobookshelf", sections: sections), animated: false, completion: nil)
    }
    private func entry(id: String, title: String, detail: String) -> CPListItem {
        let item = CPListItem(text: title, detailText: detail)
        item.handler = { [weak self] _, completion in
            PersonalPlayback.resume(id: id) { success in
                DispatchQueue.main.async {
                    if success { self?.controller?.pushTemplate(CPNowPlayingTemplate.shared, animated: true, completion: nil) }
                    else {
                        let alert = CPAlertTemplate(titleVariants: ["暂时无法播放，请在 iPhone 检查书库连接。"], actions: [CPAlertAction(title: "好", style: .default) { _ in self?.controller?.dismissTemplate(animated: true, completion: nil) }])
                        self?.controller?.presentTemplate(alert, animated: true, completion: nil)
                    }
                    completion()
                }
            }
        }
        return item
    }
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene, didDisconnect interfaceController: CPInterfaceController) { controller = nil }
}
