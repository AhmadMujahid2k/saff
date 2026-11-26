import Foundation

public typealias PrayerLogs = [String: [String: String]]

/// Prayers whose time has ended without a log count as missed.
/// This is worked out when shown, never saved, so logging any status later still overrides it.
public enum AutoMissed {
    /// Missed applies from the first logged day on; days before that were before the user started.
    public static func startKey(_ logs: PrayerLogs) -> String? { logs.keys.min() }

    /// The logged status, or `.missed` once the prayer's time is over and nothing was logged.
    public static func status(logged: PrayerStatus?, slot: PrayerSlot, now: Date, startKey: String?) -> PrayerStatus? {
        if let logged { return logged }
        guard let startKey, slot.dayKey >= startKey, slot.end <= now else { return nil }
        return .missed
    }

    /// `logs` with `.missed` filled in for every ended, unlogged prayer from the first logged day to now.
    public static func fill(_ logs: PrayerLogs, now: Date, settings: SaffSettings) -> PrayerLogs {
        guard let start = startKey(logs),
              var day = ScheduleEngine.date(fromKey: start, settings: settings)
        else { return logs }
        let cal = ScheduleEngine.calendar(settings)
        let todayKey = ScheduleEngine.dayKey(now, settings: settings)
        // Before yesterday every prayer has ended (Isha ends at the next Fajr), so no times are needed.
        let recent = cal.date(byAdding: .day, value: -1, to: now).map { ScheduleEngine.dayKey($0, settings: settings) } ?? todayKey

        var result = logs
        var key = start
        while key <= todayKey {
            var dayLog = result[key] ?? [:]
            let schedule = key >= recent ? ScheduleEngine.schedule(for: day, settings: settings) : nil
            for p in Prayer.allCases where dayLog[p.rawValue] == nil {
                if schedule == nil || schedule!.slot(p).end <= now {
                    dayLog[p.rawValue] = PrayerStatus.missed.rawValue
                }
            }
            result[key] = dayLog.isEmpty ? nil : dayLog
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
            key = ScheduleEngine.dayKey(day, settings: settings)
        }
        return result
    }
}

public struct PrayerStats: Sendable {
    public var counts: [PrayerStatus: Int] = [:]
    public var perPrayer: [Prayer: [PrayerStatus: Int]] = [:]

    public var logged: Int { counts.values.reduce(0, +) }

    public func count(_ s: PrayerStatus) -> Int { counts[s] ?? 0 }

    public func percent(_ s: PrayerStatus) -> Int {
        logged == 0 ? 0 : Int((Double(count(s)) / Double(logged) * 100).rounded())
    }

    /// Share of prayers actually prayed (jamaat, alone or late), i.e. everything except missed.
    public var prayedPercent: Int {
        logged == 0 ? 0 : Int((Double(logged - count(.missed)) / Double(logged) * 100).rounded())
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

    /// Counts statuses over `dayKeys`. Pass logs already run through `AutoMissed.fill`.
    public static func compute(dayKeys: [String], logs: PrayerLogs) -> PrayerStats {
        var stats = PrayerStats()
        for key in dayKeys {
            for p in Prayer.allCases {
                if let raw = logs[key]?[p.rawValue], let s = PrayerStatus(rawValue: raw) {
                    stats.counts[s, default: 0] += 1
                    stats.perPrayer[p, default: [:]][s, default: 0] += 1
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
