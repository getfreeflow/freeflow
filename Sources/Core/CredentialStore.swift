import Foundation

/// Where the Groq API key lives on disk.
///
/// This deliberately does *not* use the Keychain. macOS ties Keychain access to an
/// app's code signature, and a project people build from source gets a fresh ad-hoc
/// signature on every rebuild, so each new build looks like a different app trying
/// to read another app's secret, and macOS demands the login password every launch.
///
/// The tradeoff is explicit: the key is not encrypted at rest, and any process
/// running as this user could read it. That's documented in the README. It never
/// goes near the repository, and the file is owner-read/write only.
enum SecretFile {

    private static let fileName = "credentials.json"
    private static let lock = NSLock()
    /// Double optional: outer nil means "not read yet", inner nil means "no key".
    private static var cache: String??

    private struct Payload: Codable {
        var groqApiKey: String?
    }

    static func read() -> String? {
        lock.lock()
        if let cached = cache {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let value = DataFile.load(Payload.self, from: fileName)?.groqApiKey
        setCache(value)
        return value
    }

    static func write(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        let stored = (trimmed?.isEmpty ?? true) ? nil : trimmed

        DataFile.save(Payload(groqApiKey: stored), to: fileName)
        restrictPermissions()
        setCache(stored)
    }

    static var hasKey: Bool {
        guard let key = read() else { return false }
        return !key.isEmpty
    }

    static func masked() -> String? {
        guard let key = read(), key.count > 8 else { return nil }
        return String(key.prefix(4)) + "••••••••" + String(key.suffix(4))
    }

    // MARK: - Private

    private static func setCache(_ value: String?) {
        lock.lock()
        cache = .some(value)
        lock.unlock()
    }

    /// Owner read/write only, no group or other access.
    private static func restrictPermissions() {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: DataFile.url(fileName).path
        )
    }
}

/// What the UI observes. Holds only a boolean and a masked preview, so no view ever
/// touches storage while rendering.
@MainActor
final class CredentialStore: ObservableObject {
    static let shared = CredentialStore()

    @Published private(set) var hasKey = false
    @Published private(set) var masked: String?

    private init() {}

    /// Called once at launch, off the main thread.
    func load() {
        Task.detached(priority: .utility) {
            // A single read; the rest comes from the cache it populates.
            let key = SecretFile.read()
            let preview = SecretFile.masked()
            await MainActor.run {
                self.hasKey = !(key ?? "").isEmpty
                self.masked = preview
            }
        }
    }

    func save(_ key: String) {
        SecretFile.write(key)
        hasKey = SecretFile.hasKey
        masked = SecretFile.masked()
    }

    func remove() {
        SecretFile.write(nil)
        hasKey = false
        masked = nil
    }
}
