import SwiftUI
import SaffCore

struct StatsView: View {
    @Environment(AppModel.self) private var model

    enum Range: String, CaseIterable, Identifiable {
        case week = "7 days", month = "30 days", quarter = "90 days", all = "All"
        var id: String { rawValue }
    }

    @State private var range: Range = .month

    var body: some View {
        let now = Date()
        let settings = model.settings
        let keys = dayKeys(now: now, settings: settings)
        // `model.logs` is read so the view refreshes when logs change.
        let stats = { _ = model.logs; return StatsEngine.compute(dayKeys: keys, store: .shared, now: now, settings: settings) }()

        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Stats")
                    .font(.largeTitle.weight(.bold))
                    .padding(.top, 8)

                Picker("Range", selection: $range) {
                    ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(PrayerStatus.allCases) { s in
                        StatTile(status: s, percent: stats.percent(s), count: stats.count(s))
                    }
                }

                if stats.unlogged > 0 {
                    Label("\(stats.unlogged) past prayers not logged", systemImage: "questionmark.circle")
                        .font(.footnote)
                        .foregroundStyle(SaffTheme.secondaryText)
                }

                card(title: "By prayer") {
                    VStack(spacing: 12) {
                        ForEach(Prayer.allCases) { p in
                            HStack(spacing: 10) {
                                Text(p.name)
                                    .font(.subheadline.weight(.medium))
                                    .frame(width: 64, alignment: .leading)
                                StackedBar(fractions: PrayerStatus.allCases.map { (stats.percent($0, for: p), SaffTheme.color($0)) })
                                Text("\(Int((stats.percent(.jamaat, for: p) * 100).rounded()))%")
                                    .font(.saffNumber(13))
                                    .foregroundStyle(SaffTheme.color(.jamaat))
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                        Legend().frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                card(title: "History") {
                    ScrollView(.horizontal) {
                        HeatmapView(dayKeys: keys, logs: model.logs, cell: 14, spacing: 3)
                    }
                    .defaultScrollAnchor(.trailing)
                    .scrollIndicators(.hidden)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(SaffTheme.background.ignoresSafeArea())
    }

    private func dayKeys(now: Date, settings: SaffSettings) -> [String] {
        let days: Int
        switch range {
        case .week: days = 7
        case .month: days = 30
        case .quarter: days = 90
        case .all:
            let todayKey = ScheduleEngine.dayKey(now, settings: settings)
            if let first = StatsEngine.firstLoggedDay(store: .shared),
               let firstDate = ScheduleEngine.date(fromKey: first, settings: settings),
               first <= todayKey {
                let cal = ScheduleEngine.calendar(settings)
                let span = cal.dateComponents([.day], from: cal.startOfDay(for: firstDate), to: cal.startOfDay(for: now)).day ?? 0
                days = max(7, span + 1)
            } else {
                days = 7
            }
        }
        return StatsEngine.dayKeys(last: days, now: now, settings: settings)
    }

    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SaffTheme.secondaryText)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SaffTheme.card, in: .rect(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(SaffTheme.stroke))
    }
}

private struct StatTile: View {
    let status: PrayerStatus
    let percent: Int
    let count: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(status.title, systemImage: status.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SaffTheme.color(status))
            Text("\(percent)%")
                .font(.saffNumber(32, weight: .bold))
            Text("\(count) \(count == 1 ? "time" : "times")")
                .font(.caption)
                .foregroundStyle(SaffTheme.secondaryText)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(SaffTheme.empty)
                    Capsule().fill(SaffTheme.color(status)).frame(width: geo.size.width * Double(percent) / 100)
                }
            }
            .frame(height: 5)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SaffTheme.card, in: .rect(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(SaffTheme.stroke))
    }
}

private struct StackedBar: View {
    let fractions: [(Double, Color)]

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                if fractions.allSatisfy({ $0.0 == 0 }) {
                    Capsule().fill(SaffTheme.empty)
                } else {
                    ForEach(Array(fractions.enumerated()), id: \.offset) { _, item in
                        if item.0 > 0 {
                            Rectangle().fill(item.1).frame(width: max(2, (geo.size.width - 6) * item.0))
                        }
                    }
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
    }
}
