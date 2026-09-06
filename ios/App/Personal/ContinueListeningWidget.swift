import WidgetKit
import SwiftUI

struct ListeningEntry: TimelineEntry {
    let date: Date
    let title: String
    let chapter: String
    let remaining: Int
}
struct ListeningProvider: TimelineProvider {
    func placeholder(in context: Context) -> ListeningEntry { ListeningEntry(date: Date(), title: "继续听你的书", chapter: "Audiobookshelf", remaining: 0) }
    func getSnapshot(in context: Context, completion: @escaping (ListeningEntry) -> Void) { completion(entry()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ListeningEntry>) -> Void) { completion(Timeline(entries: [entry()], policy: .after(Date().addingTimeInterval(1800)))) }
    private func entry() -> ListeningEntry {
        let value = PersonalShared.defaults.dictionary(forKey: "playback") ?? [:]
        let remaining = max(0, (value["duration"] as? Double ?? 0) - (value["position"] as? Double ?? 0))
        return ListeningEntry(date: Date(), title: value["title"] as? String ?? "选一本书开始听", chapter: value["chapter"] as? String ?? "", remaining: Int(remaining / 60))
    }
}
struct ListeningWidgetView: View {
    var entry: ListeningEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("继续听", systemImage: "headphones").font(.caption).foregroundStyle(Color(red: 0.85, green: 0.73, blue: 0.46))
            Text(entry.title).font(.headline).lineLimit(3)
            if !entry.chapter.isEmpty { Text(entry.chapter).font(.caption).lineLimit(1).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            HStack { if entry.remaining > 0 { Text("还剩 \(entry.remaining) 分钟").font(.caption2) }; Spacer(); Image(systemName: "play.circle.fill").font(.title2) }
        }.foregroundStyle(.white).containerBackground(Color(red: 0.145, green: 0.169, blue: 0.275), for: .widget)
        .widgetURL(URL(string: "chaoaudiobook://resume"))
    }
}
@main
struct ContinueListeningWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ContinueListening", provider: ListeningProvider()) { entry in ListeningWidgetView(entry: entry) }
            .configurationDisplayName("继续听书").description("从上次的位置继续听。").supportedFamilies([.systemSmall, .systemMedium])
    }
}
