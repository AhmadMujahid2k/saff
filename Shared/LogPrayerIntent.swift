import AppIntents
import SaffCore
import WidgetKit

/// Logs a prayer status. Used by the widget's buttons (runs without opening the app).
/// Tapping the status that's already logged clears it.
struct LogPrayerIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Prayer"
    static var description = IntentDescription("Log how you prayed.")
    static var isDiscoverable: Bool = false

    @Parameter(title: "Day") var day: String
    @Parameter(title: "Prayer") var prayer: String
    @Parameter(title: "Status") var status: String

    init() {}

    init(day: String, prayer: Prayer, status: PrayerStatus) {
        self.day = day
        self.prayer = prayer.rawValue
        self.status = status.rawValue
    }

    func perform() async throws -> some IntentResult {
        guard let p = Prayer(rawValue: prayer), let s = PrayerStatus(rawValue: status) else {
            return .result()
        }
        SaffStore.shared.toggle(s, day: day, prayer: p)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
