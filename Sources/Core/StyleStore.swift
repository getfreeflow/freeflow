import Foundation

struct StyleRule: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var bundleIDs: [String]
    var instruction: String
    var enabled = true

    /// Built-in rules can be edited but shouldn't be silently duplicated on launch.
    var isBuiltIn = false
}

/// Per-app writing style. This is what makes dictation land as chat in Slack and as
/// prose in Mail, and unlike the hardcoded version it's fully editable.
final class StyleStore: ObservableObject {
    static let shared = StyleStore()

    private let fileName = "styles.json"

    @Published private(set) var rules: [StyleRule] = [] {
        didSet { DataFile.save(rules, to: fileName) }
    }

    private init() {
        if let saved = DataFile.load([StyleRule].self, from: fileName), !saved.isEmpty {
            rules = saved
        } else {
            rules = Self.defaults
        }
    }

    func add(name: String, bundleIDs: [String], instruction: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty, !cleanInstruction.isEmpty else { return }
        rules.append(StyleRule(name: cleanName, bundleIDs: bundleIDs, instruction: cleanInstruction))
    }

    func update(_ rule: StyleRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
    }

    func remove(_ rule: StyleRule) {
        rules.removeAll { $0.id == rule.id }
    }

    func restoreDefaults() {
        rules = Self.defaults
    }

    /// The instruction for whichever app is frontmost, if any rule matches.
    func instruction(for bundleID: String) -> String? {
        rules.first { $0.enabled && $0.bundleIDs.contains(bundleID) }?.instruction
    }

    static let defaults: [StyleRule] = [
        StyleRule(
            name: "Chat",
            bundleIDs: [
                "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.microsoft.teams2",
                "com.apple.MobileSMS", "ru.keepcoder.Telegram", "net.whatsapp.WhatsApp"
            ],
            instruction: "Keep it short and conversational, the way people actually type in chat. No greeting or sign-off.",
            isBuiltIn: true
        ),
        StyleRule(
            name: "Email",
            bundleIDs: [
                "com.apple.mail", "com.microsoft.Outlook",
                "com.readdle.smartemail-Mac", "com.superhuman.electron"
            ],
            instruction: "Write clear, professional email prose with sensible paragraph breaks.",
            isBuiltIn: true
        ),
        StyleRule(
            name: "Code",
            bundleIDs: [
                "com.apple.dt.Xcode", "com.microsoft.VSCode",
                "com.todesktop.230313mzl4w4u92", "com.googlecode.iterm2", "com.apple.Terminal"
            ],
            instruction: "Technical context. Preserve identifiers, file paths, symbols and code-like terms verbatim; do not prose-ify them.",
            isBuiltIn: true
        ),
        StyleRule(
            name: "Notes",
            bundleIDs: ["com.apple.Notes", "notion.id", "md.obsidian", "com.agiletortoise.Drafts-OSX"],
            instruction: "Note-taking context. Favour tight prose and lists over long paragraphs.",
            isBuiltIn: true
        ),
        StyleRule(
            name: "Documents",
            bundleIDs: ["com.apple.iWork.Pages", "com.microsoft.Word", "com.google.Chrome.app.docs"],
            instruction: "Long-form document context. Use full sentences and proper paragraphing.",
            isBuiltIn: true
        )
    ]
}
