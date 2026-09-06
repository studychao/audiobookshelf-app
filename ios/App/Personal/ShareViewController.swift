import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    private let status = UILabel()
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        status.text = "正在接收书籍文件…"; status.numberOfLines = 0; status.textAlignment = .center
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)
        NSLayoutConstraint.activate([status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28), status.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28), status.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        receiveFiles()
    }
    private func receiveFiles() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let group = DispatchGroup(), lock = NSLock()
        var failures = [String](), count = 0
        for provider in providers {
            let mediaIdentifier = provider.registeredTypeIdentifiers.first(where: { identifier in
                guard let type = UTType(identifier) else { return false }
                return type.conforms(to: .audio) || type.conforms(to: .image) || PersonalShared.ebookExtensions.contains(type.preferredFilenameExtension?.lowercased() ?? "")
            })
            guard let identifier = mediaIdentifier ?? (provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ? UTType.fileURL.identifier : nil) else { continue }
            group.enter()
            let receive: (URL?, Error?) -> Void = { url, error in
                defer { group.leave() }
                do {
                    if let error { throw error }
                    guard let url else { throw NSError(domain: "ShareImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取分享的文件"]) }
                    try PersonalShared.importFile(url, suggestedName: provider.suggestedName)
                    lock.lock(); count += 1; lock.unlock()
                } catch { lock.lock(); failures.append(error.localizedDescription); lock.unlock() }
            }
            if identifier == UTType.fileURL.identifier {
                provider.loadItem(forTypeIdentifier: identifier, options: nil) { item, error in
                    let url = (item as? URL) ?? (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                    receive(url, error)
                }
            } else { provider.loadFileRepresentation(forTypeIdentifier: identifier, completionHandler: receive) }
        }
        group.notify(queue: .main) {
            self.status.text = count > 0 ? "已接收 \(count) 个文件。\n打开 Audiobookshelf，在「添加」中确认书名并上传。" : "没有收到可用的音频或电子书文件。"
            if !failures.isEmpty { self.status.text! += "\n" + failures.joined(separator: "\n") }
            let done = UIButton(type: .system); done.setTitle("完成", for: .normal); done.titleLabel?.font = .preferredFont(forTextStyle: .headline); done.translatesAutoresizingMaskIntoConstraints = false
            done.addTarget(self, action: #selector(self.finish), for: .touchUpInside); self.view.addSubview(done)
            NSLayoutConstraint.activate([done.topAnchor.constraint(equalTo: self.status.bottomAnchor, constant: 24), done.centerXAnchor.constraint(equalTo: self.view.centerXAnchor), done.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)])
        }
    }
    @objc private func finish() { extensionContext?.completeRequest(returningItems: nil) }
}
