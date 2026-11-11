import SwiftUI
import SaffCore

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.everyMinute) { context in
            let now = context.date
            let settings = model.settings
            let moment = ScheduleEngine.moment(at: now, settings: settings)

            ScrollView {
                VStack(spacing: 14) {
                    header(now: now, settings: settings)
                    NowCard(moment: moment, now: now)
                    TimetableCard(moment: moment)
                    WeekCard(now: now)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(SaffTheme.background.ignoresSafeArea())
        }
    }

    private func header(now: Date, settings: SaffSettings) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(now, format: .dateTime.hour().minute())
                    .font(.saffNumber(44, weight: .bold))
                Spacer()
                Label(settings.location.name, systemImage: "location.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(SaffTheme.secondaryText)
            }
            Text(SaffFormat.gregorian(now, settings: settings))
                .font(.headline)
            Text(SaffFormat.hijri(now, settings: settings))
                .font(.subheadline)
                .foregroundStyle(SaffTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

// MARK: - Now

private struct NowCard: View {
    @Environment(AppModel.self) private var model
    let moment: PrayerMoment
    let now: Date

    var body: some View {
        let settings = model.settings
        VStack(alignment: .leading, spacing: 16) {
            if let slot = moment.current {
                HStack {
                    Label(slot.prayer.name, systemImage: slot.prayer.symbol)
                        .font(.title2.weight(.bold))
                    Spacer()
                    Text("since \(SaffFormat.timeWithPeriod(slot.start, settings: settings))")
                        .font(.footnote)
                        .foregroundStyle(SaffTheme.secondaryText)
                }
                if now < slot.jamaat {
                    CountdownRow(label: "Jamaat in", target: slot.jamaat, now: now, color: SaffTheme.accent, big: true)
                    CountdownRow(label: "Qaza in", target: slot.end, now: now, color: SaffTheme.secondaryText, big: false)
                } else {
                    CountdownRow(label: "Qaza in", target: slot.end, now: now, color: SaffTheme.color(.late), big: true)
                    Text("Jamaat was at \(SaffFormat.timeWithPeriod(slot.jamaat, settings: settings))")
                        .font(.footnote)
                        .foregroundStyle(SaffTheme.secondaryText)
                }
                WindowBar(slot: slot, now: now)
            } else {
                HStack {
                    Label("Next: \(moment.next.prayer.name)", systemImage: moment.next.prayer.symbol)
                        .font(.title2.weight(.bold))
                    Spacer()
                }
                CountdownRow(label: "Starts in", target: moment.next.start, now: now, color: SaffTheme.accent, big: true)
            }

            Divider().overlay(SaffTheme.stroke)

            let target = moment.target
            Text("How did you pray \(target.prayer.name)?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SaffTheme.secondaryText)
            StatusButtons(selected: model.status(target)) { status in
                model.toggle(status, slot: target)
            }
        }
        .padding(18)
        .background(SaffTheme.card, in: .rect(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(SaffTheme.stroke))
    }
}

struct CountdownRow: View {
    let label: String
    let target: Date
    let now: Date
    let color: Color
    let big: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(big ? .subheadline.weight(.medium) : .footnote)
                .foregroundStyle(SaffTheme.secondaryText)
            Spacer()
            Text(timerInterval: now...max(now, target), countsDown: true)
                .font(.saffNumber(big ? 34 : 17, weight: big ? .bold : .medium))
                .foregroundStyle(color)
                .multilineTextAlignment(.trailing)
        }
    }
}

/// Progress through the prayer's window, with a tick at jamaat.
private struct WindowBar: View {
    let slot: PrayerSlot
    let now: Date

    var body: some View {
        GeometryReader { geo in
            let total = slot.end.timeIntervalSince(slot.start)
            let progress = min(1, max(0, now.timeIntervalSince(slot.start) / total))
            let jamaatX = min(1, max(0, slot.jamaat.timeIntervalSince(slot.start) / total))
            ZStack(alignment: .leading) {
                Capsule().fill(SaffTheme.empty)
                Capsule()
                    .fill(LinearGradient(colors: [SaffTheme.accent, SaffTheme.color(.late)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * progress)
                Capsule()
                    .fill(.white)
                    .frame(width: 3, height: 12)
                    .offset(x: geo.size.width * jamaatX - 1.5)
            }
        }
        .frame(height: 6)
    }
}

struct StatusButtons: View {
    let selected: PrayerStatus?
    let action: (PrayerStatus) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(PrayerStatus.allCases) { status in
                let isOn = selected == status
                Button {
                    action(status)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: status.symbol)
                            .font(.system(size: 16, weight: .semibold))
                        Text(status.title)
                            .font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(isOn ? .black : SaffTheme.color(status))
                    .background(
                        isOn ? SaffTheme.color(status) : SaffTheme.color(status).opacity(0.12),
                        in: .rect(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: isOn)
            }
        }
    }
}

// MARK: - Timetable

private struct TimetableCard: View {
    @Environment(AppModel.self) private var model
    let moment: PrayerMoment

    var body: some View {
        let settings = model.settings
        let today = moment.today
        VStack(spacing: 0) {
            HStack {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                Group {
                    Text("Start")
                    Text("Jamaat")
                    Text("Ends")
                }
                .frame(width: 58, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(SaffTheme.tertiaryText)
            .padding(.bottom, 6)

            ForEach(today.slots) { slot in
                row(slot, settings: settings)
                if slot.prayer == .fajr {
                    HStack {
                        Label("Sunrise", systemImage: "sun.horizon")
                            .font(.footnote)
                            .foregroundStyle(SaffTheme.tertiaryText)
                        Spacer()
                        Text(SaffFormat.time(today.sunrise, settings: settings))
                            .font(.saffNumber(13, weight: .regular))
                            .foregroundStyle(SaffTheme.tertiaryText)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .padding(16)
        .background(SaffTheme.card, in: .rect(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(SaffTheme.stroke))
    }

    private func row(_ slot: PrayerSlot, settings: SaffSettings) -> some View {
        let isCurrent = moment.current?.id == slot.id
        let status = model.status(slot)
        return Menu {
            ForEach(PrayerStatus.allCases) { s in
                Button {
                    model.set(s, day: slot.dayKey, prayer: slot.prayer)
                } label: {
                    Label(s.title, systemImage: status == s ? "checkmark" : s.symbol)
                }
            }
            if status != nil {
                Button("Clear", systemImage: "arrow.uturn.backward", role: .destructive) {
                    model.set(nil, day: slot.dayKey, prayer: slot.prayer)
                }
            }
        } label: {
            HStack {
                HStack(spacing: 10) {
                    Circle()
                        .fill(SaffTheme.color(status))
                        .frame(width: 10, height: 10)
                    Text(slot.prayer.name)
                        .font(.body.weight(isCurrent ? .bold : .medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(SaffFormat.time(slot.start, settings: settings))
                    .frame(width: 58, alignment: .trailing)
                Text(SaffFormat.time(slot.jamaat, settings: settings))
                    .foregroundStyle(SaffTheme.accent)
                    .frame(width: 58, alignment: .trailing)
                Text(SaffFormat.time(slot.end, settings: settings))
                    .foregroundStyle(SaffTheme.secondaryText)
                    .frame(width: 58, alignment: .trailing)
            }
            .font(.saffNumber(15, weight: .medium))
            .foregroundStyle(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 8)
            .background(isCurrent ? SaffTheme.cardRaised : .clear, in: .rect(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, -8)
        }
    }
}

// MARK: - Week

private struct WeekCard: View {
    @Environment(AppModel.self) private var model
    let now: Date

    var body: some View {
        let keys = StatsEngine.dayKeys(last: 14, now: now, settings: model.settings)
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 2 weeks")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SaffTheme.secondaryText)
            HeatmapView(dayKeys: keys, logs: model.logs, cell: 18, spacing: 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            Legend()
        }
        .padding(16)
        .background(SaffTheme.card, in: .rect(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(SaffTheme.stroke))
    }
}

struct Legend: View {
    var body: some View {
        HStack(spacing: 12) {
            ForEach(PrayerStatus.allCases) { s in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(SaffTheme.color(s)).frame(width: 9, height: 9)
                    Text(s.title).font(.caption2).foregroundStyle(SaffTheme.secondaryText)
                }
            }
        }
    }
}
