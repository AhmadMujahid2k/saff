import Foundation

public enum Prayer: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case fajr, dhuhr, asr, maghrib, isha

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .fajr: "Fajr"
        case .dhuhr: "Dhuhr"
        case .asr: "Asr"
        case .maghrib: "Maghrib"
        case .isha: "Isha"
        }
    }

    public var initial: String { String(name.prefix(1)) }

    public var symbol: String {
        switch self {
        case .fajr: "sunrise.fill"
        case .dhuhr: "sun.max.fill"
        case .asr: "sun.haze.fill"
        case .maghrib: "sunset.fill"
        case .isha: "moon.stars.fill"
        }
    }
}

public enum PrayerStatus: String, CaseIterable, Codable, Identifiable, Hashable, Sendable {
    case jamaat, alone, late, missed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .jamaat: "Jamaat"
        case .alone: "Alone"
        case .late: "Late"
        case .missed: "Missed"
        }
    }

    public var symbol: String {
        switch self {
        case .jamaat: "person.3.fill"
        case .alone: "person.fill"
        case .late: "clock.badge.exclamationmark.fill"
        case .missed: "xmark"
        }
    }
}

/// How a prayer's jamaat time is decided.
public enum JamaatRule: Codable, Hashable, Sendable {
    /// Same clock time every day, e.g. Asr 4:00 PM.
    case fixed(hour: Int, minute: Int)
    /// Follows the azan, e.g. Maghrib 5 minutes after sunset.
    case afterAzan(minutes: Int)
}

public struct PrayerConfig: Codable, Hashable, Sendable {
    public var jamaat: JamaatRule
    public var alarmEnabled: Bool
    /// Minutes before jamaat the alarm rings. 0 = at jamaat time.
    public var alarmOffset: Int

    public init(jamaat: JamaatRule, alarmEnabled: Bool = true, alarmOffset: Int = 10) {
        self.jamaat = jamaat
        self.alarmEnabled = alarmEnabled
        self.alarmOffset = alarmOffset
    }
}

public struct SaffLocation: Codable, Hashable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var timeZoneID: String

    public static let lahore = SaffLocation(
        name: "Lahore", latitude: 31.5204, longitude: 74.3587, timeZoneID: "Asia/Karachi"
    )

    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID) ?? .current }
}

public struct SaffSettings: Codable, Hashable, Sendable {
    public var configs: [String: PrayerConfig]
    public var location: SaffLocation
    /// Days to shift the Hijri date (local moon sighting often differs by a day).
    public var hijriOffset: Int

    public func config(_ prayer: Prayer) -> PrayerConfig {
        configs[prayer.rawValue] ?? PrayerConfig(jamaat: .afterAzan(minutes: 10))
    }

    public mutating func setConfig(_ config: PrayerConfig, for prayer: Prayer) {
        configs[prayer.rawValue] = config
    }

    public static let `default` = SaffSettings(
        configs: [
            Prayer.fajr.rawValue: PrayerConfig(jamaat: .fixed(hour: 5, minute: 50), alarmOffset: 25),
            Prayer.dhuhr.rawValue: PrayerConfig(jamaat: .fixed(hour: 13, minute: 30)),
            Prayer.asr.rawValue: PrayerConfig(jamaat: .fixed(hour: 16, minute: 0)),
            Prayer.maghrib.rawValue: PrayerConfig(jamaat: .afterAzan(minutes: 10)),
            Prayer.isha.rawValue: PrayerConfig(jamaat: .fixed(hour: 19, minute: 0)),
        ],
        location: .lahore,
        hijriOffset: 0
    )
}
