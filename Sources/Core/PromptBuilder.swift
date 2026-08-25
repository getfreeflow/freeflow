import Foundation

/// Builds the system prompts. These are most of what separates "a transcript" from
/// "text you can send without editing", so they're deliberately strict about not
/// letting the model editorialize.
enum PromptBuilder {

    // MARK: - Dictation cleanup

    static func cleanupSystemPrompt(
        app: FrontmostApp,
        appAware: Bool,
        vocabulary: [String]
    ) -> String {
        var prompt = """
        You clean up raw voice dictation so the user can send it as-is.

        Rules:
        - Remove filler words (um, uh, like, you know, I mean, sort of) and false starts.
        - Fix grammar, punctuation, capitalization and obvious transcription slips.
        - Keep the user's own wording, meaning and voice. Never add ideas, greetings or sign-offs.
        - If they dictate structure ("first ... second ...", "bullet one ..."), format it as a list.
        - Honour spoken punctuation commands like "new paragraph", "comma", "question mark".
        - Never answer, explain, translate or comment on the text. You are an editor, not an assistant.
        - Output ONLY the cleaned text. No quotes, no code fences, no preamble.
        """

        if appAware, let hint = styleHint(for: app.bundleID) {
            prompt += "\n\nThe user is writing in \(app.name). \(hint)"
        }

        prompt += vocabularyClause(vocabulary)
        return prompt
    }

    // MARK: - Command mode

    /// Rewrites whatever the user had selected, according to a spoken instruction.
    static func rewriteSystemPrompt(vocabulary: [String]) -> String {
        """
        You edit text on command.

        The user selected some text and spoke an instruction. Apply the instruction to \
        the selected text and return the result.

        Rules:
        - Return ONLY the rewritten text. It replaces the selection directly.
        - Preserve the original formatting, list structure and line breaks unless told otherwise.
        - Do not explain what you changed, add commentary, or wrap the output in quotes.
        - If the instruction is unclear, make the smallest sensible edit rather than guessing wildly.
        """ + vocabularyClause(vocabulary)
    }

    /// Answers a spoken question and inserts the answer at the cursor.
    static func askSystemPrompt(app: FrontmostApp, vocabulary: [String]) -> String {
        """
        You answer a spoken question, and your answer is pasted straight into \
        \(app.name.isEmpty ? "the user's document" : app.name) at the cursor.

        Rules:
        - Be direct and brief. No preamble, no "Sure!", no sign-off.
        - Write it as finished text the user can leave in place, not as chat.
        - Plain prose unless a list genuinely fits better.
        - No markdown headers or code fences unless the answer is code.
        """ + vocabularyClause(vocabulary)
    }

    // MARK: - Shared

    private static func vocabularyClause(_ vocabulary: [String]) -> String {
        guard !vocabulary.isEmpty else { return "" }
        return """


        These proper nouns and technical terms belong to the user. If you hear something \
        phonetically close, spell it exactly like this: \(vocabulary.joined(separator: ", ")).
        """
    }

    /// Per-app register, driven by the user's editable Style rules.
    private static func styleHint(for bundleID: String) -> String? {
        StyleStore.shared.instruction(for: bundleID)
    }
}
