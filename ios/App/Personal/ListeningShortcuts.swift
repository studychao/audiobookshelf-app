import AppIntents

@available(iOS 16.0, *)
struct ContinueListeningIntent: AppIntent {
    static var title: LocalizedStringResource = "继续听书"
    static var description = IntentDescription("打开 Audiobookshelf，继续上次的有声书。")
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult {
        PersonalShared.defaults.set("resume", forKey: "pendingAction")
        return .result()
    }
}
@available(iOS 16.0, *)
struct AddAudiobookIntent: AppIntent {
    static var title: LocalizedStringResource = "添加书籍"
    static var openAppWhenRun: Bool = true
    func perform() async throws -> some IntentResult { PersonalShared.defaults.set("import", forKey: "pendingAction"); return .result() }
}
@available(iOS 16.0, *)
struct ListeningShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ContinueListeningIntent(), phrases: ["在 \(.applicationName) 继续听书", "Continue listening in \(.applicationName)"], shortTitle: "继续听书", systemImageName: "headphones")
        AppShortcut(intent: AddAudiobookIntent(), phrases: ["在 \(.applicationName) 添加书籍"], shortTitle: "添加书籍", systemImageName: "plus")
    }
}
