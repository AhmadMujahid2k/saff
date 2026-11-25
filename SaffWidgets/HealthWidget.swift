import AppIntents
import SaffCore
import SwiftUI
import WidgetKit

// Health Buddy widgets: today's calories, protein, steps and weight goal, read from the Drive file the Mac
// updates after every log. They refresh on their own about every 30 minutes, or right away with the ↻ button.
// The home screen widget comes in three styles (long-press → Edit Widget).

// MARK: - Styles

enum HBStyle: String, AppEnum {
    case midnight, teal, sunset

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Style"
    static var caseDisplayRepresentations: [HBStyle: DisplayRepresentation] = [
        .midnight: "Midnight",
        .teal: "Teal",
        .sunset: "Sunset",
    ]
}

/// Colors for one style.
struct HBPalette {
    let background: LinearGradient
    let accent: Color      // ring, bars, buttons
    let over: Color        // calories over target
    let track: Color       // empty part of rings and bars
    let primary: Color
    let secondary: Color
    let chip: Color        // small panels

    static func of(_ style: HBStyle) -> HBPalette {
        switch style {
        case .midnight:
            HBPalette(
                background: LinearGradient(colors: [SaffTheme.background, SaffTheme.background], startPoint: .top, endPoint: .bottom),
                accent: HealthBuddy.brand, over: HealthBuddy.warn, track: SaffTheme.empty,
                primary: .white, secondary: SaffTheme.secondaryText, chip: SaffTheme.card)
        case .teal:
            HBPalette(
                background: LinearGradient(colors: [Color(red: 0.03, green: 0.42, blue: 0.40), Color(red: 0.02, green: 0.20, blue: 0.24)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                accent: Color(red: 0.55, green: 1.0, blue: 0.88), over: Color(red: 1.0, green: 0.75, blue: 0.45),
                track: .white.opacity(0.16), primary: .white, secondary: .white.opacity(0.72), chip: .white.opacity(0.10))
        case .sunset:
            HBPalette(
                background: LinearGradient(colors: [Color(red: 0.98, green: 0.55, blue: 0.24), Color(red: 0.86, green: 0.25, blue: 0.30)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                accent: .white, over: Color(red: 0.25, green: 0.05, blue: 0.10),
                track: .white.opacity(0.25), primary: .white, secondary: .white.opacity(0.80), chip: .white.opacity(0.16))
        }
    }
}

struct HBWidgetConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Health Buddy"
    static var description = IntentDescription("Choose the widget's style.")

    @Parameter(title: "Style", default: .midnight)
    var style: HBStyle

    init() {}
}

// MARK: - Timeline

struct HBEntry: TimelineEntry {
    let date: Date
    let snapshot: HBSnapshot?
    /// Set when the latest fetch failed; `snapshot` is then the last good one, if any.
    let error: String?
    var style: HBStyle = .midnight

    var palette: HBPalette { .of(style) }
}

/// Fetches the latest numbers (or falls back to the cached ones) and schedules the next update.
private func makeTimeline(style: HBStyle) async -> Timeline<HBEntry> {
    let now = Date()
    var entry: HBEntry
    do {
        // The ↻ button has usually just fetched, so don't fetch twice.
        entry = HBEntry(date: now, snapshot: try await HealthBuddy.refresh(minAge: 60), error: nil, style: style)
    } catch {
        entry = HBEntry(date: now, snapshot: HealthBuddy.cached, error: error.localizedDescription, style: style)
    }
    let next = now.addingTimeInterval(entry.error == nil ? 30 * 60 : 15 * 60)
    return Timeline(entries: [entry], policy: .after(next))
}

struct HBConfigurableProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> HBEntry { HBEntry(date: Date(), snapshot: .sample, error: nil) }

    func snapshot(for configuration: HBWidgetConfig, in context: Context) async -> HBEntry {
        HBEntry(date: Date(), snapshot: HealthBuddy.cached ?? .sample, error: nil, style: configuration.style)
    }

    func timeline(for configuration: HBWidgetConfig, in context: Context) async -> Timeline<HBEntry> {
        await makeTimeline(style: configuration.style)
    }
}

struct HBProvider: TimelineProvider {
    func placeholder(in context: Context) -> HBEntry { HBEntry(date: Date(), snapshot: .sample, error: nil) }

    func getSnapshot(in context: Context, completion: @escaping (HBEntry) -> Void) {
        completion(HBEntry(date: Date(), snapshot: HealthBuddy.cached ?? .sample, error: nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HBEntry>) -> Void) {
        Task { completion(await makeTimeline(style: .midnight)) }
    }
}

struct HealthBuddyWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "HealthBuddy", intent: HBWidgetConfig.self, provider: HBConfigurableProvider()) { entry in
            HBHomeView(entry: entry)
                .containerBackground(for: .widget) { entry.palette.background }
        }
        .configurationDisplayName("Health Buddy")
        .description("Calories left, protein, steps and your weight goal. Long-press → Edit Widget for styles.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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

private func ratio(_ a: Int, _ b: Int) -> Double { Double(a) / Double(max(1, b)) }

/// "650" + "kcal left", or "120" + "kcal over".
private func kcalLeft(_ s: HBSnapshot) -> (value: String, label: String, over: Bool) {
    s.kcal.left >= 0 ? (grouped(s.kcal.left), "kcal left", false) : (grouped(-s.kcal.left), "kcal over", true)
}

/// First letter of the weekday for a yyyy-MM-dd date.
private func weekdayInitial(_ date: String) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    guard let d = f.date(from: date) else { return "" }
    f.dateFormat = "EEEEE"
    return f.string(from: d)
}

// MARK: - Building blocks

private struct HBRing: View {
    let snapshot: HBSnapshot
    let palette: HBPalette
    var line: CGFloat = 7
    var size: CGFloat = 20

    var body: some View {
        let s = snapshot
        let left = kcalLeft(s)
        let color = left.over ? palette.over : palette.accent
        ZStack {
            Circle().stroke(palette.track, lineWidth: line)
            Circle()
                .trim(from: 0, to: min(1, ratio(s.kcal.eaten, s.kcal.target)))
                .stroke(color, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(left.value)
                    .font(.saffNumber(size, weight: .bold))
                    .foregroundStyle(palette.primary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(left.label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.secondary)
            }
            .padding(line + 2)
        }
    }
}

private struct HBBar: View {
    let label: String
    let value: String
    let fraction: Double
    let palette: HBPalette
    var color: Color? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).foregroundStyle(palette.secondary)
                Spacer(minLength: 4)
                Text(value).foregroundStyle(palette.primary).monospacedDigit()
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    Capsule().fill(color ?? palette.accent).frame(width: geo.size.width * min(1, max(0, fraction)))
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
        let p = entry.palette
        HStack(spacing: 5) {
            Image(systemName: "heart.text.square.fill").foregroundStyle(p.accent)
            if !compact { Text("Health Buddy").fontWeight(.bold).foregroundStyle(p.primary) }
            Spacer(minLength: 0)
            if let s = entry.snapshot, s.isStale(now: entry.date) {
                Text("yesterday").foregroundStyle(p.over)
            } else if entry.error != nil, entry.snapshot != nil {
                Image(systemName: "wifi.slash").foregroundStyle(p.secondary)
            } else if let updated = entry.snapshot?.updated {
                Text(updated, style: .time).foregroundStyle(p.secondary)
            }
            Button(intent: RefreshHealthBuddyIntent()) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(p.accent)
                    .frame(width: 22, height: 22)
                    .background(p.chip, in: .circle)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 11, design: .rounded))
        .lineLimit(1)
    }
}

private struct HBBars: View {
    let snapshot: HBSnapshot
    let palette: HBPalette

    var body: some View {
        let s = snapshot
        VStack(alignment: .leading, spacing: 7) {
            HBBar(label: "Eaten", value: "\(grouped(s.kcal.eaten)) / \(grouped(s.kcal.target))",
                  fraction: ratio(s.kcal.eaten, s.kcal.target), palette: palette,
                  color: s.kcal.left < 0 ? palette.over : nil)
            HBBar(label: "Protein", value: "\(s.protein.eaten) / \(s.protein.target) g",
                  fraction: ratio(s.protein.eaten, s.protein.target), palette: palette)
            HBBar(label: "Steps", value: "\(stepsText(s.steps.count)) / \(stepsText(s.steps.target))",
                  fraction: ratio(s.steps.count ?? 0, s.steps.target), palette: palette)
        }
    }
}

private struct HBGoalLine: View {
    let snapshot: HBSnapshot
    let palette: HBPalette
    var showAhead = false

    private var text: String {
        guard let g = snapshot.goal else { return "" }
        var parts = g.kgLeft > 0 ? ["\(kg(g.kgLeft)) kg to \(Int(g.weight))", "\(g.daysLeft)d"] : ["\(Int(g.weight)) kg reached"]
        if showAhead, let a = g.ahead { parts.append(a >= 0 ? "\(kg(a)) ahead" : "\(kg(-a)) behind") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(palette.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}

/// Today's calories per meal, as small panels.
private struct HBMeals: View {
    let meals: HBSnapshot.Meals
    let palette: HBPalette

    var body: some View {
        let items: [(String, String, Int)] = [
            ("sun.horizon.fill", "Bfast", meals.breakfast),
            ("sun.max.fill", "Lunch", meals.lunch),
            ("moon.stars.fill", "Dinner", meals.dinner),
            ("cup.and.saucer.fill", "Extras", meals.snack + meals.drink),
        ]
        HStack(spacing: 6) {
            ForEach(items, id: \.1) { icon, name, kcal in
                VStack(spacing: 2) {
                    HStack(spacing: 3) {
                        Image(systemName: icon).font(.system(size: 9))
                        Text(name)
                    }
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.secondary)
                    Text(kcal > 0 ? grouped(kcal) : "–")
                        .font(.saffNumber(13, weight: .bold))
                        .foregroundStyle(kcal > 0 ? palette.primary : palette.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(palette.chip, in: .rect(cornerRadius: 10, style: .continuous))
            }
        }
    }
}

/// Progress from the milestone's start weight to its target.
private struct HBGoalProgress: View {
    let snapshot: HBSnapshot
    let palette: HBPalette

    var body: some View {
        if let g = snapshot.goal, let from = g.from, from > g.weight {
            let done = min(1, max(0, (from - snapshot.weight.kg) / (from - g.weight)))
            VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.track)
                        Capsule().fill(palette.accent).frame(width: geo.size.width * done)
                    }
                }
                .frame(height: 6)
                HStack {
                    Text("\(kg(from)) kg")
                    Spacer()
                    Text("\(Int((done * 100).rounded()))%").foregroundStyle(palette.primary)
                    Spacer()
                    Text("\(kg(g.weight)) kg")
                }
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.secondary)
            }
        }
    }
}

/// Calories eaten on each of the last 7 days: the number on top of each bar, over-target days in the warning
/// color, and the target as a labelled dashed line.
private struct HBWeekBars: View {
    let days: [HBSnapshot.DayKcal]
    let target: Int
    let palette: HBPalette

    private func short(_ n: Int) -> String { n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)" }

    var body: some View {
        let label: CGFloat = 11   // room above the bars for their numbers
        let top = Double(max(target, days.map(\.kcal).max() ?? 0))
        VStack(spacing: 3) {
            GeometryReader { geo in
                let h = geo.size.height - label
                let lineY = label + h * (1 - CGFloat(Double(target) / top))
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: lineY))
                        path.addLine(to: CGPoint(x: geo.size.width, y: lineY))
                    }
                    .stroke(palette.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(days, id: \.date) { d in
                            let over = d.kcal > target
                            VStack(spacing: 2) {
                                Text(short(d.kcal))
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                                    .foregroundStyle(over ? palette.over : palette.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(over ? palette.over : palette.accent)
                                    .frame(height: max(2, h * CGFloat(Double(d.kcal) / top)))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: geo.size.height, alignment: .bottom)
                }
            }
            HStack(spacing: 6) {
                ForEach(days, id: \.date) { d in
                    Text(weekdayInitial(d.date)).frame(maxWidth: .infinity)
                }
            }
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(palette.secondary)
        }
    }
}

/// Shown when nothing has been fetched yet.
private struct HBEmpty: View {
    let message: String
    let palette: HBPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "heart.text.square.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(palette.accent)
                Spacer()
                Button(intent: RefreshHealthBuddyIntent()) {
                    Image(systemName: "arrow.clockwise").foregroundStyle(palette.accent)
                }
                .buttonStyle(.plain)
            }
            Text(message)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(palette.secondary)
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
        let p = entry.palette
        if let s = entry.snapshot {
            switch family {
            case .systemSmall: small(s, p)
            case .systemLarge: large(s, p)
            default: medium(s, p)
            }
        } else {
            HBEmpty(message: entry.error ?? "Open Saff → Settings and paste the Health Buddy Drive link.", palette: p)
        }
    }

    private func small(_ s: HBSnapshot, _ p: HBPalette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HBHeader(entry: entry, compact: true)
            HBRing(snapshot: s, palette: p, line: 6)
                .frame(maxWidth: .infinity)
            HStack {
                Text("Protein").foregroundStyle(p.secondary)
                Spacer()
                Text("\(s.protein.eaten)/\(s.protein.target) g").foregroundStyle(p.primary).monospacedDigit()
            }
            .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
    }

    private func medium(_ s: HBSnapshot, _ p: HBPalette) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HBHeader(entry: entry)
            HStack(spacing: 14) {
                HBRing(snapshot: s, palette: p)
                    .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 7) {
                    HBBars(snapshot: s, palette: p)
                    HStack(spacing: 4) {
                        Text("\(kg(s.weight.kg)) kg")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(p.primary)
                        HBGoalLine(snapshot: s, palette: p)
                    }
                }
            }
        }
    }

    private func large(_ s: HBSnapshot, _ p: HBPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HBHeader(entry: entry)

            HStack(spacing: 14) {
                HBRing(snapshot: s, palette: p, line: 8, size: 24)
                    .frame(width: 100, height: 100)
                HBBars(snapshot: s, palette: p)
            }

            if let meals = s.meals { HBMeals(meals: meals, palette: p) }

            // weight and the goal
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(kg(s.weight.kg)) kg")
                        .font(.saffNumber(18, weight: .bold))
                        .foregroundStyle(p.primary)
                    HBGoalLine(snapshot: s, palette: p, showAhead: true)
                }
                .layoutPriority(1)
            }
            HBGoalProgress(snapshot: s, palette: p)

            if let week = s.week, !week.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("kcal · last 7 days").foregroundStyle(p.secondary)
                        Spacer(minLength: 4)
                        HStack(spacing: 3) {
                            Rectangle().fill(p.secondary).frame(width: 8, height: 1)
                            Text(grouped(s.kcal.target))
                        }
                        HStack(spacing: 3) {
                            Circle().fill(p.over).frame(width: 6, height: 6)
                            Text("over")
                        }
                    }
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(p.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    HBWeekBars(days: week, target: s.kcal.target, palette: p)
                        .frame(maxHeight: .infinity)
                    if s.deficitAvg7 != nil || s.fatKg != nil {
                        HStack(spacing: 4) {
                            if let d = s.deficitAvg7 { Text("Avg deficit \(grouped(d)) kcal/day").foregroundStyle(p.primary) }
                            if let f = s.fatKg { Text("· \(kg(f)) kg fat lost").foregroundStyle(p.secondary) }
                        }
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
                    Text(left.over ? "+\(left.value)" : left.value)
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
