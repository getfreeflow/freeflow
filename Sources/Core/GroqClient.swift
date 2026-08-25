import Foundation

enum GroqError: LocalizedError {
    case missingKey
    case rateLimited
    case unauthorized
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No Groq API key saved. Add one in Settings to enable cleanup."
        case .rateLimited:
            return "Groq's free tier is rate limited right now. Pasted the raw transcript instead."
        case .unauthorized:
            return "Groq rejected the API key. Check it in Settings."
        case .http(let code, _):
            return "Cleanup failed (HTTP \(code)). Pasted the raw transcript instead."
        case .badResponse:
            return "Couldn't read Groq's response. Pasted the raw transcript instead."
        }
    }
}

/// Thin client for Groq's OpenAI-compatible chat endpoint.
///
/// Groq runs inference on custom hardware, so a 70B model answers faster than most
/// small models elsewhere, which is what makes an LLM cleanup pass viable in a
/// dictation hot path where the user is watching a cursor and waiting.
struct GroqClient {

    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

    func complete(system: String, user: String, model: String) async throws -> String {
        guard let key = SecretFile.read(), !key.isEmpty else { throw GroqError.missingKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GroqError.badResponse }

        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw GroqError.unauthorized
        case 429:
            throw GroqError.rateLimited
        default:
            throw GroqError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw GroqError.badResponse
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Used by Settings to tell a good key from a typo without burning a dictation.
    func validateKey() async -> Bool {
        do {
            _ = try await complete(
                system: "Reply with the single word: ok",
                user: "ping",
                model: Preferences.shared.groqModel
            )
            return true
        } catch {
            return false
        }
    }
}
