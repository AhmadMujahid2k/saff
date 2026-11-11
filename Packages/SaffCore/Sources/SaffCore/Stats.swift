import Foundation

public struct PrayerStats: Sendable {
    public var counts: [PrayerStatus: Int] = [:]
    public var perPrayer: [Prayer: [PrayerStatus: Int]] = [:]
    /// Prayers in the range whose time has passed but were never logged.
    public var unlogged: Int = 0

    public var logged: Int { counts.values.reduce(0, +) }

    public func count(_ s: PrayerStatus) -> Int { counts[s] ?? 0 }

    public func percent(_ s: PrayerStatus) -> Int {
        logged == 0 ? 0 : Int((Double(count(s)) / Double(logged) * 100).rounded())
    }

    public func percent(_ s: PrayerStatus, for p: Prayer) -> Double {
        let row = perPrayer[p] ?? [:]
        let total = row.values.reduce(0, +)
        return total == 0 ? 0 : Double(row[s] ?? 0) / Double(total)
    }
}

public enum StatsEngine {
    /// Day keys for the last `days` days ending today (oldest first).
    public static func dayKeys(last days: Int, now: Date, settings: SaffSettings) -> [String] {
        let cal = ScheduleEngine.calendar(settings)
        return (0..<days).reversed().map {
            ScheduleEngine.dayKey(cal.date(byAdding: .day, value: -$0, to: now)!, settings: settings)
        }
    }

    public static func compute(dayKeys: [String], store: SaffStore, now: Date, settings: SaffSettings) -> PrayerStats {
        var stats = PrayerStats()
        let logs = store.logs
        // Days before the first log are before the user started — not "unlogged".
        let firstKey = logs.keys.min()

        for key in dayKeys {
            var day: DaySchedule?
            for p in Prayer.allCases {
                if let raw = logs[key]?[p.rawValue], let s = PrayerStatus(rawValue: raw) {
                    stats.counts[s, default: 0] += 1
                    stats.perPrayer[p, default: [:]][s, default: 0] += 1
                } else if let firstKey, key >= firstKey {
                    // Count as unlogged only once that prayer's own time is over
                    // (yesterday's Isha is still running just after midnight).
                    if day == nil, let date = ScheduleEngine.date(fromKey: key, settings: settings) {
                        day = ScheduleEngine.schedule(for: date, settings: settings)
                    }
                    if let day, day.slot(p).end <= now { stats.unlogged += 1 }
                }
            }
        }
        return stats
    }

    /// Earliest day that has any log, so "All" doesn't start years back.
    public static func firstLoggedDay(store: SaffStore) -> String? {
        store.logs.keys.min()
    }
}
