import AppKit

struct FrontmostApp: Equatable {
    let bundleID: String
    let name: String

    static let unknown = FrontmostApp(bundleID: "", name: "")
}

/// Identifies where the dictated text is about to land, so the cleanup pass can
/// match that app's register (terse in Slack, formal in Mail, and so on).
enum AppContext {
    static func frontmost() -> FrontmostApp {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .unknown }
        return FrontmostApp(
            bundleID: app.bundleIdentifier ?? "",
            name: app.localizedName ?? "the current app"
        )
    }
}
