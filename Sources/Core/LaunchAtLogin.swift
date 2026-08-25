import Foundation
import ServiceManagement

enum LaunchAtLogin {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns nil on success, or a human-readable reason it failed.
    ///
    /// This commonly fails while developing, because macOS won't register a login
    /// item for an ad-hoc signed app running out of DerivedData. It works once the
    /// app is in /Applications.
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return "macOS refused to change the login item. Move FreeFlow to your Applications folder and try again."
        }
    }
}
