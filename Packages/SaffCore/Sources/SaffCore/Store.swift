import Foundation

/// Shared storage between the app and its widgets (App Group UserDefaults).
public final class SaffStore: @unchecked Sendable {
    public static let appGroup = "group.com.ahmadmujahid.saff"
    public static let shared = SaffStore()

    private let defaults: UserDefaults
    private let logsKey = "logs.v1"        // [dayKey: [prayer: status]]
    private let settingsKey = "settings.v1"

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Self.appGroup) ?? .standard
    }

    // MARK: Settings

    public var settings: SaffSettings {
        get {
            guard let data = defaults.data(forKey: settingsKey),
                  let s = try? JSONDecoder().decode(SaffSettings.self, from: data)
            else { return .default }
            return s
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: settingsKey)
            }
        }
    }

    // MARK: Logs

    public var logs: [String: [String: String]] {
        defaults.dictionary(forKey: logsKey) as? [String: [String: String]] ?? [:]
    }

    public func status(day: String, prayer: Prayer) -> PrayerStatus? {
        logs[day]?[prayer.rawValue].flatMap(PrayerStatus.init(rawValue:))
    }

    public func statuses(day: String) -> [Prayer: PrayerStatus] {
        var result: [Prayer: PrayerStatus] = [:]
        for (k, v) in logs[day] ?? [:] {
            if let p = Prayer(rawValue: k), let s = PrayerStatus(rawValue: v) { result[p] = s }
        }
        return result
    }

    public func set(_ status: PrayerStatus?, day: String, prayer: Prayer) {
        var all = logs
        var dayLog = all[day] ?? [:]
        dayLog[prayer.rawValue] = status?.rawValue
        all[day] = dayLog.isEmpty ? nil : dayLog
        defaults.set(all, forKey: logsKey)
    }

    /// Tapping the status that's already logged clears it (undo a mis-tap).
    public func toggle(_ status: PrayerStatus, day: String, prayer: Prayer) {
        let currentStatus = self.status(day: day, prayer: prayer)
        set(currentStatus == status ? nil : status, day: day, prayer: prayer)
    }
}
