import SaffCore
import SwiftUI
import WidgetKit

struct SaffEntry: TimelineEntry {
    let date: Date
    let settings: SaffSettings
    let moment: PrayerMoment
    let logs: [String: [String: String]]

    func status(_ slot: PrayerSlot) -> PrayerStatus? {
        logs[slot.dayKey]?[slot.prayer.rawValue].flatMap(PrayerStatus.init(rawValue:))
    }

    var hijri: String { SaffFormat.hijri(date, settings: settings) }

    /// What to count down to right now, e.g. ("Jamaat in", 4:00 PM).
    var primaryCountdown: (label: String, target: Date, color: Color) {
        if let slot = moment.current {
            if date < slot.jamaat { return ("Jamaat in", slot.jamaat, SaffTheme.accent) }
            return ("Qaza in", slot.end, SaffTheme.color(.late))
        }
        return ("\(moment.next.prayer.name) in", moment.next.start, SaffTheme.accent)
    }

    /// The slot the header describes: the running prayer, or the next one in the gap after sunrise.
    var headline: PrayerSlot { moment.current ?? moment.next }

    static func make(at date: Date) -> SaffEntry {
        let store = SaffStore.shared
        let settings = store.settings
        return SaffEntry(
            date: date,
            settings: settings,
            moment: ScheduleEngine.moment(at: date, settings: settings),
            logs: store.logs
        )
    }
}

struct SaffProvider: TimelineProvider {
    func placeholder(in context: Context) -> SaffEntry { .make(at: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (SaffEntry) -> Void) {
        completion(.make(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SaffEntry>) -> Void) {
        let now = Date()
        let settings = SaffStore.shared.settings
        let dates = [now] + ScheduleEngine.events(from: now, hours: 24, settings: settings)
        let entries = dates.map { SaffEntry.make(at: $0) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
