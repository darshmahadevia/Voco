import Foundation

@main
struct UsageStatsSmoke {
    static func main() {
        let suite = "voco.usage-test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("Missing test defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 12))!
        var stats = UsageStats.load(defaults: defaults)
        stats.record(text: "Hello, world! 123", seconds: 2, date: date)
        stats.record(text: "A second dictation", seconds: 3, date: date)
        stats.record(text: "   ...   ", seconds: 9, date: date)
        stats.record(text: "invalid duration", seconds: -.infinity, date: date)
        precondition(stats.days["2026-10-09"]?.words == 6)
        precondition(stats.days["2026-10-09"]?.sessions == 2)
        precondition(stats.days["2026-10-09"]?.seconds == 5)
        stats.dailyGoal = 1000
        stats.typingWpm = 60
        stats.save(defaults: defaults)
        let restored = UsageStats.load(defaults: defaults)
        precondition(restored.dailyGoal == 1000 && restored.typingWpm == 60)
        precondition(restored.days["2026-10-09"]?.words == 6)
        let stored = String(data: defaults.data(forKey: "usageStats.v1")!, encoding: .utf8)!
        precondition(!stored.contains("Hello") && !stored.contains("dictation"))
        defaults.set(Data("corrupt".utf8), forKey: "usageStats.v1")
        precondition(UsageStats.load(defaults: defaults).days.isEmpty)
        print("Usage stats: accumulation, persistence, preferences, empty speech and privacy passed.")
    }
}
