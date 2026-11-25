import SaffCore
import SwiftUI
import WidgetKit

@main
struct SaffWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SaffHomeWidget()
        SaffLockWidget()
        HealthBuddyWidget()
        HealthBuddyLockWidget()
    }
}

struct SaffHomeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "SaffHome", intent: SaffWidgetConfig.self, provider: SaffConfigurableProvider()) { entry in
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
