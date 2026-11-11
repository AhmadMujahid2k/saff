import Foundation
import Adhan

/// One prayer on one day: when it starts, when it becomes qaza, and when jamaat is.
public struct PrayerSlot: Identifiable, Hashable, Sendable {
    public let prayer: Prayer
    /// "yyyy-MM-dd" of the day this prayer belongs to (Isha after midnight belongs to the previous day).
    public let dayKey: String
    public let start: Date
    public let end: Date
    public let jamaat: Date

    public var id: String { "\(dayKey)-\(prayer.rawValue)" }

    public func contains(_ date: Date) -> Bool { start <= date && date < end }
}

public struct DaySchedule: Hashable, Sendable {
    public let dayKey: String
    public let sunrise: Date
    public let slots: [PrayerSlot]

    public func slot(_ prayer: Prayer) -> PrayerSlot {
        slots.first { $0.prayer == prayer }!
    }
}

/// Where we are right now relative to the prayers.
public struct PrayerMoment: Hashable, Sendable {
    /// Prayer whose time is running now (nil between sunrise and Dhuhr).
    public let current: PrayerSlot?
    /// Next prayer to start.
    public let next: PrayerSlot
    /// The prayer the widget's log buttons apply to: the current one,
    /// or the one that most recently ended (e.g. Fajr in the morning gap).
    public let target: PrayerSlot
    /// Today's (by the clock) schedule.
    public let today: DaySchedule
}

public enum ScheduleEngine {
    public static func calendar(_ settings: SaffSettings) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = settings.location.timeZone
        return cal
    }

    public static func dayKey(_ date: Date, settings: SaffSettings) -> String {
        let c = calendar(settings).dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public static func date(fromKey key: String, settings: SaffSettings) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar(settings).date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    private static func rawTimes(for day: Date, settings: SaffSettings) -> PrayerTimes? {
        let cal = calendar(settings)
        let comps = cal.dateComponents([.year, .month, .day], from: day)
        var params = CalculationMethod.karachi.params
        params.madhab = .hanafi
        let coords = Coordinates(latitude: settings.location.latitude, longitude: settings.location.longitude)
        return PrayerTimes(coordinates: coords, date: comps, calculationParameters: params)
    }

    public static func schedule(for day: Date, settings: SaffSettings) -> DaySchedule {
        let cal = calendar(settings)
        let key = dayKey(day, settings: settings)
        guard let t = rawTimes(for: day, settings: settings),
              let nextDay = cal.date(byAdding: .day, value: 1, to: day),
              let tn = rawTimes(for: nextDay, settings: settings)
        else {
            fatalError("Prayer times unavailable for \(key)")
        }

        let starts: [Prayer: Date] = [.fajr: t.fajr, .dhuhr: t.dhuhr, .asr: t.asr, .maghrib: t.maghrib, .isha: t.isha]
        let ends: [Prayer: Date] = [.fajr: t.sunrise, .dhuhr: t.asr, .asr: t.maghrib, .maghrib: t.isha, .isha: tn.fajr]

        let slots = Prayer.allCases.map { p -> PrayerSlot in
            let start = starts[p]!
            let jamaat: Date
            switch settings.config(p).jamaat {
            case let .fixed(hour, minute):
                jamaat = cal.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? start
            case let .afterAzan(minutes):
                jamaat = start.addingTimeInterval(TimeInterval(minutes * 60))
            }
            return PrayerSlot(prayer: p, dayKey: key, start: start, end: ends[p]!, jamaat: jamaat)
        }
        return DaySchedule(dayKey: key, sunrise: t.sunrise, slots: slots)
    }

    /// Slots from yesterday through tomorrow, in order.
    public static func slots(around now: Date, settings: SaffSettings) -> [PrayerSlot] {
        let cal = calendar(settings)
        return (-1...1).flatMap { offset -> [PrayerSlot] in
            let day = cal.date(byAdding: .day, value: offset, to: now)!
            return schedule(for: day, settings: settings).slots
        }
    }

    public static func moment(at now: Date, settings: SaffSettings) -> PrayerMoment {
        let all = slots(around: now, settings: settings)
        let current = all.first { $0.contains(now) }
        let next = all.first { $0.start > now }!
        let lastEnded = all.last { $0.end <= now }!
        return PrayerMoment(
            current: current,
            next: next,
            target: current ?? lastEnded,
            today: schedule(for: now, settings: settings)
        )
    }

    /// Times when what a widget shows changes (starts, jamaats, ends) over the next `hours`.
    public static func events(from now: Date, hours: Double = 24, settings: SaffSettings) -> [Date] {
        let horizon = now.addingTimeInterval(hours * 3600)
        let cal = calendar(settings)
        let days = (0...2).map { cal.date(byAdding: .day, value: $0, to: now)! }
        var dates = Set<Date>()
        for day in days {
            let s = schedule(for: day, settings: settings)
            dates.insert(s.sunrise)
            for slot in s.slots {
                dates.insert(slot.start)
                dates.insert(slot.end)
                dates.insert(slot.jamaat)
                // Also refresh just after jamaat so "jamaat in" switches to "qaza in".
                dates.insert(slot.jamaat.addingTimeInterval(1))
            }
            // Midnight: the date line changes.
            if let midnight = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: day)) {
                dates.insert(midnight)
            }
        }
        return dates.filter { $0 > now && $0 <= horizon }.sorted()
    }
}
