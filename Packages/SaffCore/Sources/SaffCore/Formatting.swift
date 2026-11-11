import Foundation

public enum SaffFormat {
    private static let hijriMonths = [
        "Muharram", "Safar", "Rabi al-Awwal", "Rabi al-Thani", "Jumada al-Ula", "Jumada al-Akhirah",
        "Rajab", "Sha'ban", "Ramadan", "Shawwal", "Dhul Qadah", "Dhul Hijjah",
    ]

    /// Hijri date. The Islamic day begins at Maghrib, so after sunset it shows tomorrow's date.
    public static func hijri(_ now: Date, settings: SaffSettings) -> String {
        let maghrib = ScheduleEngine.schedule(for: now, settings: settings).slot(.maghrib).start
        var cal = Calendar(identifier: .islamicUmmAlQura)
        cal.timeZone = settings.location.timeZone
        let shift = settings.hijriOffset + (now >= maghrib ? 1 : 0)
        let date = cal.date(byAdding: .day, value: shift, to: now) ?? now
        let c = cal.dateComponents([.day, .month, .year], from: date)
        let month = hijriMonths[max(0, min(11, (c.month ?? 1) - 1))]
        return "\(c.day ?? 1) \(month) \(c.year ?? 0) AH"
    }

    public static func time(_ date: Date, settings: SaffSettings) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = settings.location.timeZone
        f.dateFormat = "h:mm"
        return f.string(from: date)
    }

    public static func timeWithPeriod(_ date: Date, settings: SaffSettings) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = settings.location.timeZone
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    public static func gregorian(_ date: Date, settings: SaffSettings, style: String = "EEEE, d MMMM") -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = settings.location.timeZone
        f.dateFormat = style
        return f.string(from: date)
    }

    /// "1h 05m" / "12m" — for static text where a live timer isn't needed.
    public static func duration(_ interval: TimeInterval) -> String {
        let mins = max(0, Int(interval / 60))
        return mins >= 60 ? String(format: "%dh %02dm", mins / 60, mins % 60) : "\(mins)m"
    }
}
