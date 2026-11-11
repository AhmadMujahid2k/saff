import ActivityKit
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

    /// Custom sound if one is bundled (Saff/Sounds/alarm.caf, ≤ 30 s, not in the repo), else the system alarm.
    private static let customSoundName = "alarm.caf"
    private static var alarmSound: AlertConfiguration.AlertSound {
        Bundle.main.url(forResource: customSoundName, withExtension: nil) != nil ? .named(customSoundName) : .default
    }
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
        if let existing = try? manager.alarms {
            for alarm in existing where alarm.id != test?.id {
                try? manager.cancel(id: alarm.id)
            }
        }
        var count = 0
        var failures: [String] = []
        var lastDated: Date?
        let cal = ScheduleEngine.calendar(settings)
        let now = Date()

        // Each prayer is scheduled independently, so one failure doesn't drop the rest.
        for prayer in Prayer.allCases {
            let config = settings.config(prayer)
            guard config.alarmEnabled else { continue }
            let title = alarmTitle(prayer, offset: config.alarmOffset)
            do {
                switch config.jamaat {
                case let .fixed(hour, minute):
                    let total = ((hour * 60 + minute - config.alarmOffset) % 1440 + 1440) % 1440
                    let rule = Alarm.Schedule.relative(.init(
                        time: .init(hour: total / 60, minute: total % 60),
                        repeats: .weekly([.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
                    ))
                    try await add(prayer: prayer, title: title, schedule: rule)

                case .afterAzan:
                    for dayOffset in 0..<followAzanDays {
                        guard let day = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
                        let slot = ScheduleEngine.schedule(for: day, settings: settings).slot(prayer)
                        let ring = slot.jamaat.addingTimeInterval(TimeInterval(-config.alarmOffset * 60))
                        guard ring > now else { continue }
                        try await add(prayer: prayer, title: title, schedule: .fixed(ring))
                        lastDated = max(lastDated ?? ring, ring)
                    }
                }
                // Several dated alarms for Maghrib, but it's still one prayer's alarm to the user.
                count += 1
            } catch {
                failures.append("\(prayer.name): \(error.localizedDescription)")
            }
        }
        scheduledCount = count
        datedAlarmsUntil = lastDated
        lastError = failures.isEmpty ? nil : failures.joined(separator: "\n")
    }

    /// Last day the "after azan" (Maghrib) alarms are scheduled for; they need the app opened before then.
    private(set) var datedAlarmsUntil: Date?

    #if DEBUG
    /// Demo screenshots: show the count the real sync would, without scheduling anything.
    func showDemoCount(settings: SaffSettings) {
        access = .allowed
        scheduledCount = Prayer.allCases.filter { settings.config($0).alarmEnabled }.count
    }
    #endif

    /// The pending test alarm, if any (kept across re-syncs).
    private(set) var test: (id: UUID, fireDate: Date)?

    /// One-off alarm 10 seconds from now, to hear the sound.
    @MainActor
    func scheduleTest() async {
        guard await requestAccess() else { return }
        cancelTest()
        let id = UUID()
        let fire = Date().addingTimeInterval(10)
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
                sound: Self.alarmSound
            )
        )
    }
}
