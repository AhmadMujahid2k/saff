#if canImport(SwiftUI)
import SwiftUI

public enum SaffTheme {
    public static let background = Color(red: 0.035, green: 0.043, blue: 0.055)
    public static let card = Color(red: 0.075, green: 0.086, blue: 0.106)
    public static let cardRaised = Color(red: 0.11, green: 0.125, blue: 0.15)
    public static let stroke = Color.white.opacity(0.07)
    public static let empty = Color.white.opacity(0.07)
    public static let secondaryText = Color.white.opacity(0.55)
    public static let tertiaryText = Color.white.opacity(0.32)
    public static let accent = Color(red: 0.24, green: 0.85, blue: 0.58)

    public static func color(_ status: PrayerStatus?) -> Color {
        switch status {
        case .jamaat: Color(red: 0.24, green: 0.85, blue: 0.58)   // emerald
        case .alone: Color(red: 1.0, green: 0.78, blue: 0.27)     // gold
        case .late: Color(red: 1.0, green: 0.48, blue: 0.29)      // orange
        case .missed: Color(red: 0.93, green: 0.27, blue: 0.36)   // crimson
        case nil: empty
        }
    }
}

public extension Font {
    static func saffNumber(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

/// Grid of days (columns) × prayers (rows), colored by status.
public struct HeatmapView: View {
    let dayKeys: [String]
    let logs: [String: [String: String]]
    let cell: CGFloat
    let spacing: CGFloat
    let showLabels: Bool

    public init(dayKeys: [String], logs: [String: [String: String]], cell: CGFloat = 12, spacing: CGFloat = 3, showLabels: Bool = true) {
        self.dayKeys = dayKeys
        self.logs = logs
        self.cell = cell
        self.spacing = spacing
        self.showLabels = showLabels
    }

    public var body: some View {
        HStack(alignment: .top, spacing: spacing + 2) {
            if showLabels {
                VStack(spacing: spacing) {
                    ForEach(Prayer.allCases) { p in
                        Text(p.initial)
                            .font(.system(size: cell * 0.7, weight: .semibold, design: .rounded))
                            .foregroundStyle(SaffTheme.tertiaryText)
                            .frame(height: cell)
                    }
                }
            }
            HStack(spacing: spacing) {
                ForEach(dayKeys, id: \.self) { key in
                    VStack(spacing: spacing) {
                        ForEach(Prayer.allCases) { p in
                            let status = logs[key]?[p.rawValue].flatMap(PrayerStatus.init(rawValue:))
                            RoundedRectangle(cornerRadius: cell * 0.28, style: .continuous)
                                .fill(SaffTheme.color(status))
                                .frame(width: cell, height: cell)
                        }
                    }
                }
            }
        }
    }
}
#endif
