#if DEBUG
import SaffCore
import SwiftUI

/// Debug-only helpers for README screenshots (Simulator):
///   -demo            fill ~2 months of sample logs
///   -screen <name>   open "today" | "stats" | "settings" | "widgets"
enum DemoMode {
    private static let args = ProcessInfo.processInfo.arguments

    static var isOn: Bool { args.contains("-demo") }

    static var screen: String? {
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func seedIfNeeded() {
        guard isOn else { return }
        let store = SaffStore.shared
        let settings = store.settings
        let now = Date()
        let moment = ScheduleEngine.moment(at: now, settings: settings)
        var rng = SeededGenerator(seed: 1447)

        for key in StatsEngine.dayKeys(last: 60, now: now, settings: settings) {
            for prayer in Prayer.allCases {
                let slot = ScheduleEngine.schedule(
                    for: ScheduleEngine.date(fromKey: key, settings: settings)!, settings: settings
                ).slot(prayer)
                // Only prayers that are over, plus the one running now.
                guard slot.end <= now || slot.id == moment.current?.id else {
                    store.set(nil, day: key, prayer: prayer)
                    continue
                }
                store.set(sample(prayer, &rng), day: key, prayer: prayer)
            }
        }
    }

    private static func sample(_ prayer: Prayer, _ rng: inout SeededGenerator) -> PrayerStatus {
        let r = Double.random(in: 0..<1, using: &rng)
        // Fajr is the hardest to catch in jamaat; Maghrib the easiest.
        let jamaat: Double = switch prayer {
        case .fajr: 0.52
        case .maghrib: 0.85
        default: 0.72
        }
        if r < jamaat { return .jamaat }
        if r < jamaat + 0.15 { return .alone }
        if r < jamaat + 0.24 { return .late }
        return .missed
    }
}

/// Deterministic RNG so screenshots are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 33)) &* 0xff51afd7ed558ccd
        return z ^ (z >> 33)
    }
}

/// The home-screen widgets drawn at iPhone sizes, for screenshots.
struct WidgetGallery: View {
    var body: some View {
        let entry = SaffEntry.make(at: Date())
        // A moment before a jamaat, to show the green "Jamaat in" countdown too.
        let next = entry.moment.next
        let beforeJamaat = SaffEntry.make(at: max(next.start, next.jamaat.addingTimeInterval(-12 * 60 - 34)))
        ScrollView {
            VStack(spacing: 22) {
                HStack(spacing: 22) {
                    frame(SmallView(entry: entry), width: 170, height: 170)
                    frame(SmallView(entry: beforeJamaat), width: 170, height: 170)
                }
                frame(MediumView(entry: entry), width: 364, height: 170)
                frame(LargeView(entry: entry), width: 364, height: 382)
            }
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .background(
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.20, blue: 0.22), Color(red: 0.03, green: 0.05, blue: 0.09)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }

    private func frame<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> some View {
        view
            .padding(16)
            .frame(width: width, height: height)
            .background(SaffTheme.background, in: .rect(cornerRadius: 24, style: .continuous))
    }
}
#endif
