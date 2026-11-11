import AlarmKit
import SaffCore
import SwiftUI

struct SaffAlarmMetadata: AlarmMetadata {
    var prayer: String
}

/// Schedules real alarms (ring even on silent) before each jamaat.
/// Fixed jamaat times → one repeating daily alarm.
/// Jamaat that follows the azan (Maghrib) → one alarm per day for the next 14 days,
/// topped up whenever the app is opened.
@Observable
final class AlarmScheduler {
    enum Access { case unknown, allowed, denied }

    private(set) var access: Access = .unknown
    private(set) var lastError: String?
    private(set) var scheduledCount = 0

    private let manager = AlarmManager.shared
    private let followAzanDays = 14

    @MainActor
    func requestAccess() async -> Bool {
        switch manager.authorizationState {
        case .authorized:
            access = .allowed
            return true
        case .denied:
            access = .denied
            return false
        case .notDetermined:
            let state = (try? await manager.requestAuthorization()) ?? .denied
            access = state == .authorized ? .allowed : .denied
            return state == .authorized
        @unknown default:
            return false
        }
    }

    private var isSyncing = false
    private var pending: SaffSettings?

    /// Replace all alarms with ones matching `settings`. Calls made while a sync
    /// is running are coalesced so alarms are never scheduled twice.
    @MainActor
    func sync(settings: SaffSettings) async {
        pending = settings
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        while let next = pending {
            pending = nil
            await replaceAll(settings: next)
        }
    }

    @MainActor
    private func replaceAll(settings: SaffSettings) async {
        guard await requestAccess() else { return }
        lastError = nil
        do {
            for alarm in try manager.alarms where alarm.id != test?.id {
                try? manager.cancel(id: alarm.id)
            }
            var count = 0
            let cal = ScheduleEngine.calendar(settings)
            let now = Date()

            for prayer in Prayer.allCases {
                let config = settings.config(prayer)
                guard config.alarmEnabled else { continue }
                let title = alarmTitle(prayer, offset: config.alarmOffset)

                switch config.jamaat {
                case let .fixed(hour, minute):
                    let total = ((hour * 60 + minute - config.alarmOffset) % 1440 + 1440) % 1440
                    let rule = Alarm.Schedule.relative(.init(
                        time: .init(hour: total / 60, minute: total % 60),
                        repeats: .weekly([.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
                    ))
                    try await add(prayer: prayer, title: title, schedule: rule)
                    count += 1

                case .afterAzan:
                    for dayOffset in 0..<followAzanDays {
                        guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                        let slot = ScheduleEngine.schedule(for: day, settings: settings).slot(prayer)
                        let ring = slot.jamaat.addingTimeInterval(TimeInterval(-config.alarmOffset * 60))
                        guard ring > now else { continue }
                        try await add(prayer: prayer, title: title, schedule: .fixed(ring))
                    }
                    // Several dated alarms, but it's still one prayer's alarm to the user.
                    count += 1
                }
            }
            scheduledCount = count
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// The pending test alarm, if any (kept across re-syncs).
    private(set) var test: (id: UUID, fireDate: Date)?

    /// One-off alarm a minute from now, to hear the sound.
    @MainActor
    func scheduleTest() async {
        guard await requestAccess() else { return }
        cancelTest()
        let id = UUID()
        let fire = Date().addingTimeInterval(60)
        do {
            try await add(prayer: .fajr, title: "Saff test alarm", schedule: .fixed(fire), id: id)
            test = (id, fire)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    @MainActor
    func cancelTest() {
        guard let t = test else { return }
        try? manager.cancel(id: t.id)
        test = nil
    }

    private func alarmTitle(_ prayer: Prayer, offset: Int) -> LocalizedStringResource {
        offset == 0 ? "\(prayer.name) jamaat now" : "\(prayer.name) jamaat in \(offset) min"
    }

    @MainActor
    private func add(prayer: Prayer, title: LocalizedStringResource, schedule: Alarm.Schedule, id: UUID = UUID()) async throws {
        let alert = AlarmPresentation.Alert(
            title: title,
            stopButton: AlarmButton(text: "Done", textColor: .black, systemImageName: "checkmark")
        )
        let attributes = AlarmAttributes<SaffAlarmMetadata>(
            presentation: AlarmPresentation(alert: alert),
            metadata: SaffAlarmMetadata(prayer: prayer.rawValue),
            tintColor: SaffTheme.accent
        )
        _ = try await manager.schedule(
            id: id,
            configuration: .alarm(
                schedule: schedule,
                attributes: attributes,
                sound: .named("hayya_ala_salah.caf")
            )
        )
    }
}
