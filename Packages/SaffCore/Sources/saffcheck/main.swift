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
let stats = StatsEngine.compute(dayKeys: StatsEngine.dayKeys(last: 7, now: now, settings: settings), store: store, now: now, settings: settings)
print("Stats check: logged \(stats.logged), late \(stats.percent(.late))%, unlogged \(stats.unlogged)")
print("OK")
