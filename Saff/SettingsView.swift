import SwiftUI
import SaffCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    alarmStatus
                } footer: {
                    Text("Alarms ring even on silent. Fixed jamaat times repeat daily; Maghrib follows sunset and is refreshed each time you open Saff.")
                }

                ForEach(Prayer.allCases) { prayer in
                    PrayerSettingsSection(prayer: prayer)
                }

                Section("Hijri date") {
                    Stepper(value: Binding(
                        get: { model.settings.hijriOffset },
                        set: { v in model.update { $0.hijriOffset = v } }
                    ), in: -2...2) {
                        HStack {
                            Text("Adjust")
                            Spacer()
                            Text(model.settings.hijriOffset == 0 ? "None" : String(format: "%+d day", model.settings.hijriOffset))
                                .foregroundStyle(SaffTheme.secondaryText)
                        }
                    }
                    Text(SaffFormat.hijri(Date(), settings: model.settings))
                        .foregroundStyle(SaffTheme.accent)
                }

                Section {
                    LabeledContent("Location", value: model.settings.location.name)
                    LabeledContent("Method", value: "Karachi · Hanafi Asr")
                    LabeledContent("Isha ends", value: "At Fajr")
                } header: {
                    Text("Prayer times")
                } footer: {
                    Text("Start and end times are calculated automatically.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(SaffTheme.background.ignoresSafeArea())
            .navigationTitle("Settings")
        }
    }

    @ViewBuilder private var alarmStatus: some View {
        let alarms = model.alarms
        switch alarms.access {
        case .denied:
            Label("Alarms are off. Allow them in Settings → Saff.", systemImage: "alarm.waves.left.and.right")
                .foregroundStyle(SaffTheme.color(.missed))
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        default:
            if let error = alarms.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(SaffTheme.color(.late))
            } else {
                Label("\(alarms.scheduledCount) of 5 prayer alarms on", systemImage: "alarm.fill")
            }
            Button("Re-schedule alarms") {
                Task { await alarms.sync(settings: model.settings) }
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let test = alarms.test, test.fireDate > context.date {
                    HStack {
                        Image(systemName: "alarm.waves.left.and.right.fill")
                            .foregroundStyle(SaffTheme.accent)
                            .symbolEffect(.pulse)
                        Text("Test alarm rings in")
                        Text(timerInterval: context.date...test.fireDate, countsDown: true)
                            .font(.saffNumber(17, weight: .bold))
                            .foregroundStyle(SaffTheme.accent)
                        Spacer()
                        Button("Cancel", role: .cancel) { alarms.cancelTest() }
                            .buttonStyle(.bordered)
                    }
                } else {
                    Button("Test alarm in 1 minute") {
                        Task { await alarms.scheduleTest() }
                    }
                }
            }
        }
    }
}

private struct PrayerSettingsSection: View {
    @Environment(AppModel.self) private var model
    let prayer: Prayer

    private enum Mode: String, CaseIterable { case fixed = "Fixed time", afterAzan = "After azan" }

    var body: some View {
        let config = model.settings.config(prayer)
        let today = ScheduleEngine.schedule(for: Date(), settings: model.settings).slot(prayer)

        Section {
            Picker("Jamaat", selection: Binding(
                get: { if case .fixed = config.jamaat { Mode.fixed } else { Mode.afterAzan } },
                set: { mode in
                    edit {
                        switch mode {
                        case .fixed:
                            let c = Calendar.current.dateComponents([.hour, .minute], from: today.jamaat)
                            $0.jamaat = .fixed(hour: c.hour ?? 0, minute: c.minute ?? 0)
                        case .afterAzan:
                            $0.jamaat = .afterAzan(minutes: 10)
                        }
                    }
                }
            )) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
            }

            switch config.jamaat {
            case let .fixed(hour, minute):
                DatePicker("Jamaat time", selection: Binding(
                    get: { Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date() },
                    set: { date in
                        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                        edit { $0.jamaat = .fixed(hour: c.hour ?? 0, minute: c.minute ?? 0) }
                    }
                ), displayedComponents: .hourAndMinute)
            case let .afterAzan(minutes):
                Stepper("\(minutes) min after azan", value: Binding(
                    get: { minutes },
                    set: { v in edit { $0.jamaat = .afterAzan(minutes: v) } }
                ), in: 0...60)
            }

            Toggle("Alarm", isOn: Binding(
                get: { config.alarmEnabled },
                set: { v in edit { $0.alarmEnabled = v } }
            ))
            if config.alarmEnabled {
                Stepper(config.alarmOffset == 0 ? "At jamaat time" : "\(config.alarmOffset) min before", value: Binding(
                    get: { config.alarmOffset },
                    set: { v in edit { $0.alarmOffset = v } }
                ), in: 0...60, step: 5)
            }
        } header: {
            Label(prayer.name, systemImage: prayer.symbol)
        } footer: {
            let s = model.settings
            Text("Today: starts \(SaffFormat.timeWithPeriod(today.start, settings: s)) · jamaat \(SaffFormat.timeWithPeriod(today.jamaat, settings: s)) · ends \(SaffFormat.timeWithPeriod(today.end, settings: s))")
        }
    }

    private func edit(_ change: (inout PrayerConfig) -> Void) {
        model.update { settings in
            var c = settings.config(prayer)
            change(&c)
            settings.setConfig(c, for: prayer)
        }
    }
}
