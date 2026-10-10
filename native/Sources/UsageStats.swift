import Foundation

struct UsageDay: Codable {
    var words = 0
    var seconds: Double = 0
    var sessions = 0
}

struct UsageStats: Codable {
    var days: [String: UsageDay] = [:]
    var dailyGoal = 500
    var typingWpm = 40

    static func load(defaults: UserDefaults) -> UsageStats {
        guard let data = defaults.data(forKey: "usageStats.v1"),
              let stats = try? JSONDecoder().decode(UsageStats.self, from: data),
              (100...10000).contains(stats.dailyGoal), (10...200).contains(stats.typingWpm),
              stats.days.values.allSatisfy({ $0.words >= 0 && $0.seconds.isFinite && $0.seconds >= 0 && $0.sessions >= 0 }) else {
            return UsageStats()
        }
        return stats
    }

    func save(defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: "usageStats.v1")
    }

    mutating func record(text: String, seconds: Double, date: Date = Date()) {
        let words = text.split(whereSeparator: { $0.isWhitespace }).filter {
            $0.contains(where: { $0.isLetter || $0.isNumber })
        }.count
        guard words > 0, seconds.isFinite, seconds >= 0 else { return }
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return }
        let key = String(format: "%04d-%02d-%02d", year, month, day)
        var activity = days[key] ?? UsageDay()
        activity.words += words
        activity.seconds += seconds
        activity.sessions += 1
        days[key] = activity
    }

    var json: [String: Any] {
        ["days": days.mapValues { ["words": $0.words, "seconds": $0.seconds, "sessions": $0.sessions] as [String: Any] },
         "dailyGoal": dailyGoal, "typingWpm": typingWpm]
    }
}
