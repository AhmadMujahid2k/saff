import SwiftUI
import SaffCore
import WidgetKit

@main
struct SaffApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(SaffTheme.accent)
                .task { await model.alarms.sync(settings: model.settings) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.reload()
                // Keep Maghrib's day-by-day alarms topped up.
                Task { await model.alarms.sync(settings: model.settings) }
            }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            Tab("Today", systemImage: "clock.fill") { TodayView() }
            Tab("Stats", systemImage: "chart.bar.fill") { StatsView() }
            Tab("Settings", systemImage: "gearshape.fill") { SettingsView() }
        }
    }
}

@Observable
final class AppModel {
    private let store = SaffStore.shared
    let alarms = AlarmScheduler()

    var settings: SaffSettings
    var logs: [String: [String: String]]

    init() {
        settings = store.settings
        logs = store.logs
    }

    /// Re-read shared storage (the widget may have logged something).
    func reload() {
        settings = store.settings
        logs = store.logs
    }

    func status(_ slot: PrayerSlot) -> PrayerStatus? {
        logs[slot.dayKey]?[slot.prayer.rawValue].flatMap(PrayerStatus.init(rawValue:))
    }

    func toggle(_ status: PrayerStatus, slot: PrayerSlot) {
        store.toggle(status, day: slot.dayKey, prayer: slot.prayer)
        logs = store.logs
        WidgetCenter.shared.reloadAllTimelines()
    }

    func set(_ status: PrayerStatus?, day: String, prayer: Prayer) {
        store.set(status, day: day, prayer: prayer)
        logs = store.logs
        WidgetCenter.shared.reloadAllTimelines()
    }

    func update(_ change: (inout SaffSettings) -> Void) {
        change(&settings)
        store.settings = settings
        WidgetCenter.shared.reloadAllTimelines()
        let s = settings
        Task { await alarms.sync(settings: s) }
    }
}
