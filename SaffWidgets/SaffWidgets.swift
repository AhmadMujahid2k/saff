import SaffCore
import SwiftUI
import WidgetKit

@main
struct SaffWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SaffHomeWidget()
        SaffLockWidget()
    }
}

struct SaffHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SaffHome", provider: SaffProvider()) { entry in
            HomeWidgetView(entry: entry)
                .containerBackground(for: .widget) { SaffTheme.background }
        }
        .configurationDisplayName("Saff")
        .description("Prayer times, countdowns and one-tap logging.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct SaffLockWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SaffLock", provider: SaffProvider()) { entry in
            LockWidgetView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Saff · Next prayer")
        .description("Countdown to jamaat or qaza.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct HomeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SaffEntry

    var body: some View {
        switch family {
        case .systemSmall: SmallView(entry: entry)
        case .systemLarge: LargeView(entry: entry)
        default: MediumView(entry: entry)
        }
    }
}

// MARK: - Building blocks

struct PrayerHeader: View {
    let entry: SaffEntry

    var body: some View {
        let slot = entry.headline
        HStack(spacing: 6) {
            Image(systemName: slot.prayer.symbol)
                .foregroundStyle(SaffTheme.accent)
            Text(slot.prayer.name)
                .fontWeight(.bold)
            if entry.moment.current == nil {
                Text("next").foregroundStyle(SaffTheme.tertiaryText)
            }
        }
        .font(.system(size: 15, design: .rounded))
        .foregroundStyle(.white)
    }
}

struct BigCountdown: View {
    let entry: SaffEntry
    var size: CGFloat = 30

    var body: some View {
        let c = entry.primaryCountdown
        VStack(alignment: .leading, spacing: 0) {
            Text(c.label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(SaffTheme.secondaryText)
            Text(timerInterval: entry.date...max(entry.date, c.target), countsDown: true)
                .font(.saffNumber(size, weight: .bold))
                .foregroundStyle(c.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

/// "Qaza in 1:05:00" shown under the main countdown while waiting for jamaat.
struct SecondaryCountdown: View {
    let entry: SaffEntry

    var body: some View {
        if let slot = entry.moment.current, entry.date < slot.jamaat {
            HStack(spacing: 4) {
                Text("Qaza in")
                Text(timerInterval: entry.date...slot.end, countsDown: true)
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(SaffTheme.secondaryText)
        } else if let slot = entry.moment.current {
            Text("Ends \(SaffFormat.timeWithPeriod(slot.end, settings: entry.settings))")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(SaffTheme.secondaryText)
        } else {
            Text("Jamaat \(SaffFormat.timeWithPeriod(entry.moment.next.jamaat, settings: entry.settings))")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(SaffTheme.secondaryText)
        }
    }
}

struct LogButton: View {
    let entry: SaffEntry
    let status: PrayerStatus
    var compact = false

    var body: some View {
        let target = entry.moment.target
        let isOn = entry.status(target) == status
        Button(intent: LogPrayerIntent(day: target.dayKey, prayer: target.prayer, status: status)) {
            VStack(spacing: compact ? 2 : 4) {
                Image(systemName: status.symbol)
                    .font(.system(size: compact ? 12 : 14, weight: .semibold))
                Text(status.title)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold, design: .rounded))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(isOn ? .black : SaffTheme.color(status))
            .background(
                isOn ? SaffTheme.color(status) : SaffTheme.color(status).opacity(0.14),
                in: .rect(cornerRadius: 12, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TodayDots: View {
    let entry: SaffEntry

    var body: some View {
        HStack(spacing: 5) {
            ForEach(entry.moment.today.slots) { slot in
                VStack(spacing: 3) {
                    Circle()
                        .fill(SaffTheme.color(entry.status(slot)))
                        .frame(width: 9, height: 9)
                    Text(slot.prayer.initial)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(entry.moment.current?.id == slot.id ? .white : SaffTheme.tertiaryText)
                }
            }
        }
    }
}

// MARK: - Small

struct SmallView: View {
    let entry: SaffEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PrayerHeader(entry: entry)
            Spacer(minLength: 0)
            BigCountdown(entry: entry, size: 28)
            SecondaryCountdown(entry: entry)
            Spacer(minLength: 0)
            TodayDots(entry: entry)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Medium

struct MediumView: View {
    let entry: SaffEntry

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    PrayerHeader(entry: entry)
                    Spacer(minLength: 0)
                }
                BigCountdown(entry: entry, size: 30)
                SecondaryCountdown(entry: entry)
                Spacer(minLength: 0)
                TimesRow(entry: entry, slot: entry.headline)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Log \(entry.moment.target.prayer.name)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(SaffTheme.tertiaryText)
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        LogButton(entry: entry, status: .jamaat)
                        LogButton(entry: entry, status: .alone)
                    }
                    GridRow {
                        LogButton(entry: entry, status: .late)
                        LogButton(entry: entry, status: .missed)
                    }
                }
            }
            .frame(width: 140)
        }
    }
}

struct TimesRow: View {
    let entry: SaffEntry
    let slot: PrayerSlot

    var body: some View {
        HStack(spacing: 10) {
            item("Start", slot.start, .white)
            item("Jamaat", slot.jamaat, SaffTheme.accent)
            item("End", slot.end, SaffTheme.secondaryText)
        }
    }

    private func item(_ label: String, _ date: Date, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(SaffTheme.tertiaryText)
            Text(SaffFormat.time(date, settings: entry.settings))
                .font(.saffNumber(13))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Large

struct LargeView: View {
    let entry: SaffEntry

    var body: some View {
        let s = entry.settings
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(SaffFormat.gregorian(entry.date, settings: s, style: "EEE d MMM"))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(entry.hijri)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(SaffTheme.accent)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    PrayerHeader(entry: entry)
                    BigCountdown(entry: entry, size: 30)
                }
                Spacer(minLength: 8)
                SecondaryCountdown(entry: entry)
                    .padding(.bottom, 6)
            }

            HStack(spacing: 6) {
                ForEach(PrayerStatus.allCases) { LogButton(entry: entry, status: $0, compact: true) }
            }
            .frame(height: 40)

            VStack(spacing: 3) {
                ForEach(entry.moment.today.slots) { slot in
                    let isCurrent = entry.moment.current?.id == slot.id
                    HStack {
                        Circle().fill(SaffTheme.color(entry.status(slot))).frame(width: 7, height: 7)
                        Text(slot.prayer.name)
                            .font(.system(size: 12, weight: isCurrent ? .bold : .medium, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        Text(SaffFormat.time(slot.start, settings: s)).frame(width: 38, alignment: .trailing)
                        Text(SaffFormat.time(slot.jamaat, settings: s)).foregroundStyle(SaffTheme.accent).frame(width: 38, alignment: .trailing)
                        Text(SaffFormat.time(slot.end, settings: s)).foregroundStyle(SaffTheme.secondaryText).frame(width: 38, alignment: .trailing)
                    }
                    .font(.saffNumber(12, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isCurrent ? SaffTheme.cardRaised : .clear, in: .rect(cornerRadius: 6))
                }
            }

            Spacer(minLength: 0)

            HStack(alignment: .bottom) {
                HeatmapView(
                    dayKeys: StatsEngine.dayKeys(last: 21, now: entry.date, settings: s),
                    logs: entry.logs, cell: 8, spacing: 2, showLabels: false
                )
                Spacer(minLength: 8)
                let stats = StatsEngine.compute(
                    dayKeys: StatsEngine.dayKeys(last: 30, now: entry.date, settings: s),
                    store: .shared, now: entry.date, settings: s
                )
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(stats.percent(.jamaat))%")
                        .font(.saffNumber(22, weight: .bold))
                        .foregroundStyle(SaffTheme.color(.jamaat))
                    Text("jamaat · 30d")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(SaffTheme.tertiaryText)
                }
            }
        }
    }
}

// MARK: - Lock screen

struct LockWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SaffEntry

    var body: some View {
        let c = entry.primaryCountdown
        let slot = entry.headline
        switch family {
        case .accessoryCircular:
            if let current = entry.moment.current {
                ProgressView(timerInterval: current.start...current.end, countsDown: true) {
                    Text(current.prayer.initial)
                } currentValueLabel: {
                    Text(current.prayer.initial).font(.system(size: 18, weight: .bold, design: .rounded))
                }
                .progressViewStyle(.circular)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: 0) {
                        Text(slot.prayer.initial).font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(SaffFormat.time(slot.start, settings: entry.settings)).font(.saffNumber(11))
                    }
                }
            }
        case .accessoryInline:
            Text("\(slot.prayer.name) · Jamaat \(SaffFormat.timeWithPeriod(slot.jamaat, settings: entry.settings))")
        default:
            VStack(alignment: .leading, spacing: 0) {
                Label(slot.prayer.name, systemImage: slot.prayer.symbol)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                HStack(spacing: 4) {
                    Text(c.label)
                    Text(timerInterval: entry.date...max(entry.date, c.target), countsDown: true)
                        .monospacedDigit()
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("Jamaat \(SaffFormat.time(slot.jamaat, settings: entry.settings)) · Ends \(SaffFormat.time(slot.end, settings: entry.settings))")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
