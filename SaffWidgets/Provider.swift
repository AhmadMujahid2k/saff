import AppIntents
import SaffCore
import SwiftUI
import WidgetKit

/// Options in "Edit Widget" (long-press the home screen widget).
struct SaffWidgetConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Saff"
    static var description = IntentDescription("Choose how many days the large widget's history shows.")

    @Parameter(title: "Days shown", description: "Days in the large widget's heatmap and jamaat %.", default: 21, inclusiveRange: (1, 30))
    var days: Int

    init() {}
}

struct SaffEntry: TimelineEntry {
    let date: Date
    let settings: SaffSettings
    let moment: PrayerMoment
    let logs: [String: [String: String]]
    /// Days in the large widget's heatmap and jamaat %.
    var days: Int = 21

    /// `logs` already has auto-missed filled in for this entry's time.
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
        return ("\(moment.next.name) in", moment.next.start, SaffTheme.accent)
    }

    /// The slot the header describes: the running prayer, or the next one in the gap after sunrise.
    var headline: PrayerSlot { moment.current ?? moment.next }

    static func make(at date: Date, days: Int = 21) -> SaffEntry {
        let store = SaffStore.shared
        let settings = store.settings
        return SaffEntry(
            date: date,
            settings: settings,
            moment: ScheduleEngine.moment(at: date, settings: settings),
            logs: AutoMissed.fill(store.logs, now: date, settings: settings),
            days: min(30, max(1, days))
        )
    }

    /// Entries for now and every moment the widget's content changes over the next day.
    static func timeline(days: Int = 21) -> Timeline<SaffEntry> {
        let now = Date()
        let settings = SaffStore.shared.settings
        let dates = [now] + ScheduleEngine.events(from: now, hours: 24, settings: settings)
        return Timeline(entries: dates.map { make(at: $0, days: days) }, policy: .atEnd)
    }
}

struct SaffProvider: TimelineProvider {
    func placeholder(in context: Context) -> SaffEntry { .make(at: Date()) }

    func getSnapshot(in context: Context, completion: @escaping (SaffEntry) -> Void) {
        completion(.make(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SaffEntry>) -> Void) {
        completion(SaffEntry.timeline())
    }
}

/// Home screen widget provider: same timeline, plus the "Edit Widget" options.
struct SaffConfigurableProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SaffEntry { .make(at: Date()) }

    func snapshot(for configuration: SaffWidgetConfig, in context: Context) async -> SaffEntry {
        .make(at: Date(), days: configuration.days)
    }

    func timeline(for configuration: SaffWidgetConfig, in context: Context) async -> Timeline<SaffEntry> {
        SaffEntry.timeline(days: configuration.days)
    }
}
