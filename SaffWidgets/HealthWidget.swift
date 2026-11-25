import SaffCore
import SwiftUI
import WidgetKit

// Health Buddy widgets: today's calories, protein, steps and weight goal, read from the Drive file the Mac
// updates after every log. They refresh on their own about every 30 minutes, or right away with the ↻ button.

struct HBEntry: TimelineEntry {
    let date: Date
    let snapshot: HBSnapshot?
    /// Set when the latest fetch failed; `snapshot` is then the last good one, if any.
    let error: String?
}

struct HBProvider: TimelineProvider {
    func placeholder(in context: Context) -> HBEntry { HBEntry(date: Date(), snapshot: .sample, error: nil) }

    func getSnapshot(in context: Context, completion: @escaping (HBEntry) -> Void) {
        completion(HBEntry(date: Date(), snapshot: HealthBuddy.cached ?? .sample, error: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HBEntry>) -> Void) {
        Task {
            let now = Date()
            var entry: HBEntry
            do {
                // The ↻ button has usually just fetched, so don't fetch twice.
                entry = HBEntry(date: now, snapshot: try await HealthBuddy.refresh(minAge: 60), error: nil)
            } catch {
                entry = HBEntry(date: now, snapshot: HealthBuddy.cached, error: error.localizedDescription)
            }
            let next = now.addingTimeInterval(entry.error == nil ? 30 * 60 : 15 * 60)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

struct HealthBuddyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HealthBuddy", provider: HBProvider()) { entry in
            HBHomeView(entry: entry)
                .containerBackground(for: .widget) { SaffTheme.background }
        }
        .configurationDisplayName("Health Buddy")
        .description("Calories left, protein, steps and your weight goal.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct HealthBuddyLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HealthBuddyLock", provider: HBProvider()) { entry in
            HBLockView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Health Buddy · Calories")
        .description("Calories left today.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Helpers

private func grouped(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }

private func stepsText(_ n: Int?) -> String {
    guard let n else { return "–" }
    return n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)"
}

private func kg(_ v: Double) -> String { String(format: "%.1f", v) }

/// "650 left" or "120 over", and the color to show it in.
private func kcalLeft(_ s: HBSnapshot) -> (value: String, label: String, color: Color) {
    s.kcal.left >= 0
        ? (grouped(s.kcal.left), "kcal left", HealthBuddy.brand)
        : (grouped(-s.kcal.left), "kcal over", HealthBuddy.warn)
}

private struct HBRing: View {
    let snapshot: HBSnapshot
    var line: CGFloat = 7

    var body: some View {
        let s = snapshot
        let fraction = min(1, Double(s.kcal.eaten) / Double(max(1, s.kcal.target)))
        let left = kcalLeft(s)
        ZStack {
            Circle().stroke(SaffTheme.empty, lineWidth: line)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(left.color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(left.value)
                    .font(.saffNumber(20, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(left.label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(SaffTheme.secondaryText)
            }
            .padding(line + 2)
        }
    }
}

private struct HBBar: View {
    let label: String
    let value: String
    let fraction: Double
    var color: Color = HealthBuddy.brand

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).foregroundStyle(SaffTheme.secondaryText)
                Spacer(minLength: 4)
                Text(value).foregroundStyle(.white).monospacedDigit()
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SaffTheme.empty)
                    Capsule().fill(color).frame(width: geo.size.width * min(1, max(0, fraction)))
                }
            }
            .frame(height: 5)
        }
    }
}

/// Title, when the numbers were made (or a warning), and the ↻ button.
private struct HBHeader: View {
    let entry: HBEntry
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "heart.text.square.fill").foregroundStyle(HealthBuddy.brand)
            if !compact { Text("Health Buddy").fontWeight(.bold).foregroundStyle(.white) }
            Spacer(minLength: 0)
            if let s = entry.snapshot, s.isStale(now: entry.date) {
                Text("yesterday").foregroundStyle(HealthBuddy.warn)
            } else if entry.error != nil, entry.snapshot != nil {
                Image(systemName: "wifi.slash").foregroundStyle(SaffTheme.tertiaryText)
            } else if let updated = entry.snapshot?.updated {
                Text(updated, style: .time).foregroundStyle(SaffTheme.tertiaryText)
            }
            Button(intent: RefreshHealthBuddyIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(HealthBuddy.brand)
                    .frame(width: 22, height: 22)
                    .background(HealthBuddy.brand.opacity(0.15), in: .circle)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11, design: .rounded))
        .lineLimit(1)
    }
}

private struct HBGoalLine: View {
    let snapshot: HBSnapshot

    var body: some View {
        if let g = snapshot.goal {
            Text(g.kgLeft > 0 ? "\(kg(g.kgLeft)) kg to \(Int(g.weight)) · \(g.daysLeft)d" : "\(Int(g.weight)) kg reached")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(g.kgLeft > 0 ? SaffTheme.secondaryText : SaffTheme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// Shown when nothing has been fetched yet.
private struct HBEmpty: View {
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(HealthBuddy.brand)
                Spacer()
                Button(intent: RefreshHealthBuddyIntent()) {
                    Image(systemName: "arrow.clockwise").foregroundStyle(HealthBuddy.brand)
                }
                .buttonStyle(.plain)
            }
            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(SaffTheme.secondaryText)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Home screen

struct HBHomeView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HBEntry

    var body: some View {
        if let s = entry.snapshot {
            switch family {
            case .systemSmall: small(s)
            default: medium(s)
            }
        } else {
            HBEmpty(message: entry.error ?? "Open Saff → Settings and paste the Health Buddy Drive link.")
        }
    }

    private func small(_ s: HBSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HBHeader(entry: entry, compact: true)
            HBRing(snapshot: s, line: 6)
                .frame(maxWidth: .infinity)
            HStack {
                Text("Protein").foregroundStyle(SaffTheme.secondaryText)
                Spacer()
                Text("\(s.protein.eaten)/\(s.protein.target) g").foregroundStyle(.white).monospacedDigit()
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
    }

    private func medium(_ s: HBSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HBHeader(entry: entry)
            HStack(spacing: 14) {
                HBRing(snapshot: s)
                    .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 7) {
                    HBBar(label: "Eaten", value: "\(grouped(s.kcal.eaten)) / \(grouped(s.kcal.target))",
                          fraction: Double(s.kcal.eaten) / Double(max(1, s.kcal.target)),
                          color: kcalLeft(s).color)
                    HBBar(label: "Protein", value: "\(s.protein.eaten) / \(s.protein.target) g",
                          fraction: Double(s.protein.eaten) / Double(max(1, s.protein.target)))
                    HBBar(label: "Steps", value: "\(stepsText(s.steps.count)) / \(stepsText(s.steps.target))",
                          fraction: Double(s.steps.count ?? 0) / Double(max(1, s.steps.target)))
                    HStack(spacing: 4) {
                        Text("\(kg(s.weight.kg)) kg")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        HBGoalLine(snapshot: s)
                    }
                }
            }
        }
    }
}

// MARK: - Lock screen (no buttons there; it follows the home screen widget's refreshes)

struct HBLockView: View {
    @Environment(\.widgetFamily) private var family
    let entry: HBEntry

    var body: some View {
        if let s = entry.snapshot {
            let left = kcalLeft(s)
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(min(s.kcal.eaten, s.kcal.target)), in: 0...Double(max(1, s.kcal.target))) {
                    Image(systemName: "fork.knife")
                } currentValueLabel: {
                    Text(s.kcal.left >= 0 ? left.value : "+\(left.value)")
                        .minimumScaleFactor(0.5)
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryInline:
                Text("\(left.value) \(left.label) · \(s.protein.eaten) g protein")
            default:
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(left.value) \(left.label)")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text("Protein \(s.protein.eaten)/\(s.protein.target) g · \(stepsText(s.steps.count)) steps")
                        .font(.system(size: 12, design: .rounded))
                    if let g = s.goal, g.kgLeft > 0 {
                        Text("\(kg(g.kgLeft)) kg to \(Int(g.weight)) · \(g.daysLeft)d")
                            .font(.system(size: 12, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            switch family {
            case .accessoryInline: Text("Health Buddy: not connected")
            default: Image(systemName: "heart.text.square")
            }
        }
    }
}
