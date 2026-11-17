import Foundation
import SaffCore

// Prints today's schedule and the current moment, to sanity-check the core logic.
let settings = SaffSettings.default
let now = Date()
let today = ScheduleEngine.schedule(for: now, settings: settings)

print("Lahore — \(SaffFormat.gregorian(now, settings: settings)) · \(SaffFormat.hijri(now, settings: settings))")
print("Sunrise \(SaffFormat.timeWithPeriod(today.sunrise, settings: settings))")
for slot in today.slots {
    let t = { SaffFormat.timeWithPeriod($0, settings: settings) }
    print("\(slot.prayer.name.padding(toLength: 8, withPad: " ", startingAt: 0)) start \(t(slot.start))  jamaat \(t(slot.jamaat))  end \(t(slot.end))")
}

let m = ScheduleEngine.moment(at: now, settings: settings)
print("Current: \(m.current?.prayer.name ?? "none") · Next: \(m.next.prayer.name) · Log target: \(m.target.prayer.name) (\(m.target.dayKey))")
print("Next widget refreshes: \(ScheduleEngine.events(from: now, settings: settings).prefix(5).map { SaffFormat.timeWithPeriod($0, settings: settings) })")

// Store round-trip in a throwaway suite.
let store = SaffStore(defaults: UserDefaults(suiteName: "saffcheck.\(UUID())")!)
store.toggle(.jamaat, day: m.target.dayKey, prayer: m.target.prayer)
precondition(store.status(day: m.target.dayKey, prayer: m.target.prayer) == .jamaat)
store.toggle(.jamaat, day: m.target.dayKey, prayer: m.target.prayer)
precondition(store.status(day: m.target.dayKey, prayer: m.target.prayer) == nil)
store.set(.late, day: m.target.dayKey, prayer: .fajr)
let stats = StatsEngine.compute(dayKeys: StatsEngine.dayKeys(last: 7, now: now, settings: settings), logs: store.logs)
print("Stats check: logged \(stats.logged), late \(stats.percent(.late))%")

// Auto-missed: ended + unlogged = missed, from the first logged day; running/future prayers stay empty.
let cal = ScheduleEngine.calendar(settings)
let d0 = cal.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))!
let k0 = ScheduleEngine.dayKey(d0, settings: settings)
let k1 = ScheduleEngine.dayKey(cal.date(byAdding: .day, value: 1, to: d0)!, settings: settings)
let k2 = ScheduleEngine.dayKey(cal.date(byAdding: .day, value: 2, to: d0)!, settings: settings)
let day2 = ScheduleEngine.schedule(for: cal.date(byAdding: .day, value: 2, to: d0)!, settings: settings)
let duringAsr = day2.slot(.asr).start.addingTimeInterval(60)
let filled = AutoMissed.fill([k0: ["isha": "jamaat"]], now: duringAsr, settings: settings)
precondition(filled[k0] == ["fajr": "missed", "dhuhr": "missed", "asr": "missed", "maghrib": "missed", "isha": "jamaat"])
precondition(filled[k1]?.count == 5 && filled[k1]?.values.allSatisfy { $0 == "missed" } == true)
precondition(filled[k2] == ["fajr": "missed", "dhuhr": "missed"], "Asr is running, so only Fajr and Dhuhr: \(filled[k2] ?? [:])")
// Just after midnight yesterday's Isha is still running, so it must not be missed yet.
let afterMidnight = cal.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 0, minute: 30))!
precondition(AutoMissed.fill([k0: ["fajr": "jamaat"]], now: afterMidnight, settings: settings)[k2]?["isha"] == nil)
precondition(AutoMissed.status(logged: nil, slot: day2.slot(.dhuhr), now: duringAsr, startKey: k0) == .missed)
precondition(AutoMissed.status(logged: .late, slot: day2.slot(.dhuhr), now: duringAsr, startKey: k0) == .late)
precondition(AutoMissed.status(logged: nil, slot: day2.slot(.dhuhr), now: duringAsr, startKey: nil) == nil)
precondition(AutoMissed.fill([:], now: duringAsr, settings: settings).isEmpty)
print("Auto-missed check: OK")

// Jumu'ah: Friday's Dhuhr uses its own time; other days keep Dhuhr's.
var jsettings = settings
jsettings.jumuah = SaffSettings.defaultJumuah
let friday = cal.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 12))!
let thursday = cal.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 12))!
let fri = ScheduleEngine.schedule(for: friday, settings: jsettings).slot(.dhuhr)
let thu = ScheduleEngine.schedule(for: thursday, settings: jsettings).slot(.dhuhr)
precondition(fri.isJumuah && fri.name == "Jumu'ah" && cal.component(.hour, from: fri.jamaat) == 13 && cal.component(.minute, from: fri.jamaat) == 30)
precondition(!thu.isJumuah && thu.name == "Dhuhr" && cal.component(.minute, from: thu.jamaat) == 30)
precondition(!ScheduleEngine.schedule(for: friday, settings: settings).slot(.dhuhr).isJumuah)
print("Jumu'ah check: OK")
print("OK")
