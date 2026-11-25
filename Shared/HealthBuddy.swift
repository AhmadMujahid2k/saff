import AppIntents
import Foundation
import SaffCore
import SwiftUI
import WidgetKit

/// Today's numbers from Health Buddy (the calorie tracker), as published by its `/api/widget` endpoint.
struct HBSnapshot: Codable, Equatable {
    struct Kcal: Codable, Equatable { let eaten: Int; let target: Int; let floor: Int; let left: Int }
    struct Protein: Codable, Equatable { let eaten: Int; let target: Int }
    struct Steps: Codable, Equatable { let count: Int?; let target: Int }
    struct Weight: Codable, Equatable { let kg: Double; let date: String; let start: Double }
    struct Goal: Codable, Equatable {
        let label: String?
        let weight: Double
        let date: String
        let kgLeft: Double
        let daysLeft: Int
        let ahead: Double?
    }

    let date: String
    let updatedAt: String
    let kcal: Kcal
    let protein: Protein
    let steps: Steps
    let burn: Int?
    let weight: Weight
    let goal: Goal?

    /// When the Mac produced these numbers.
    var updated: Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: updatedAt) ?? ISO8601DateFormatter().date(from: updatedAt)
    }

    /// The numbers are for an earlier day (nothing logged yet today), so "eaten" no longer means today.
    func isStale(now: Date = Date()) -> Bool {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: now) != date
    }

    /// Sample numbers for placeholders and the widget picker.
    static let sample = HBSnapshot(
        date: "2026-11-25", updatedAt: "2026-11-25T12:00:00Z",
        kcal: .init(eaten: 1150, target: 1800, floor: 1200, left: 650),
        protein: .init(eaten: 62, target: 80),
        steps: .init(count: 6200, target: 8000),
        burn: 2600,
        weight: .init(kg: 100.2, date: "2026-11-25", start: 109),
        goal: .init(label: "Two digits", weight: 99, date: "2026-12-08", kgLeft: 1.2, daysLeft: 13, ahead: 0.8)
    )
}

/// Reads Health Buddy's numbers from a Google Drive file the Mac updates after every log
/// ("anyone with the link can view"), and keeps the last good copy for the widgets.
/// The link is pasted in Settings, so it never has to be written into the code.
enum HealthBuddy {
    private static var defaults: UserDefaults { UserDefaults(suiteName: SaffStore.appGroup) ?? .standard }
    private static let linkKey = "hb.link"
    private static let snapshotKey = "hb.snapshot.v1"
    private static let errorKey = "hb.lastError"
    private static let fetchedKey = "hb.fetchedAt"

    static let kinds = ["HealthBuddy", "HealthBuddyLock"]
    static let brand = Color(red: 0.08, green: 0.72, blue: 0.65)   // Health Buddy teal, lifted for the dark theme
    static let warn = Color(red: 1.0, green: 0.62, blue: 0.25)

    /// The Drive share link as pasted, e.g. https://drive.google.com/file/d/<id>/view?usp=sharing
    static var link: String {
        get { defaults.string(forKey: linkKey) ?? "" }
        set { defaults.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: linkKey) }
    }

    /// The file ID inside any Drive link shape (…/d/<id>/…, ?id=<id>), or nil.
    static func fileID(in link: String) -> String? {
        let patterns = [#"/d/([A-Za-z0-9_-]{20,})"#, #"[?&]id=([A-Za-z0-9_-]{20,})"#, #"^([A-Za-z0-9_-]{20,})$"#]
        let range = NSRange(link.startIndex..., in: link)
        for p in patterns {
            guard let regex = try? NSRegularExpression(pattern: p),
                  let m = regex.firstMatch(in: link, range: range),
                  let r = Range(m.range(at: 1), in: link)
            else { continue }
            return String(link[r])
        }
        return nil
    }

    static var cached: HBSnapshot? {
        defaults.data(forKey: snapshotKey).flatMap { try? JSONDecoder().decode(HBSnapshot.self, from: $0) }
    }

    /// Why the last fetch failed, or nil if it worked.
    static var lastError: String? { defaults.string(forKey: errorKey) }

    enum FetchError: LocalizedError {
        case noLink, badLink, badResponse(Int), notJSON
        var errorDescription: String? {
            switch self {
            case .noLink: "Paste the Health Buddy Drive link in Saff → Settings."
            case .badLink: "That doesn't look like a Google Drive file link."
            case .badResponse(let code): "Google Drive answered with error \(code)."
            case .notJSON: "Couldn't read the file. Is it shared as \"anyone with the link\"?"
            }
        }
    }

    /// Fetches the latest numbers and caches them; on failure the last good numbers stay cached.
    /// Skips the network if it fetched in the last `minAge` seconds (the widget button and timeline both ask).
    @discardableResult
    static func refresh(minAge: TimeInterval = 0) async throws -> HBSnapshot {
        if minAge > 0, let last = defaults.object(forKey: fetchedKey) as? Date,
           Date().timeIntervalSince(last) < minAge, let cached {
            return cached
        }
        do {
            guard !link.isEmpty else { throw FetchError.noLink }
            guard let id = fileID(in: link) else { throw FetchError.badLink }
            // The timestamp keeps any cache in between from handing back an old copy.
            let stamp = Int(Date().timeIntervalSince1970)
            guard let url = URL(string: "https://drive.google.com/uc?export=download&id=\(id)&t=\(stamp)") else {
                throw FetchError.badLink
            }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                throw FetchError.badResponse(http.statusCode)
            }
            guard let snapshot = try? JSONDecoder().decode(HBSnapshot.self, from: data) else { throw FetchError.notJSON }
            defaults.set(data, forKey: snapshotKey)
            defaults.set(Date(), forKey: fetchedKey)
            defaults.removeObject(forKey: errorKey)
            return snapshot
        } catch {
            defaults.set(error.localizedDescription, forKey: errorKey)
            throw error
        }
    }

    static func reloadWidgets() {
        for kind in kinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
    }
}

/// The widget's ↻ button: fetch the latest numbers now instead of waiting for the next scheduled update.
struct RefreshHealthBuddyIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Health Buddy"
    static var description = IntentDescription("Fetch today's calories from Health Buddy now.")
    static var isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        _ = try? await HealthBuddy.refresh()
        HealthBuddy.reloadWidgets()
        return .result()
    }
}
