import Foundation
import Security

// MARK: - Wire model

enum AssistantBlock: Codable, Equatable {
    case text(String)
    case toolUse(id: String, name: String, inputJSON: String)
    case toolResult(id: String, content: String, isError: Bool)

    var toolUseInfo: (id: String, name: String, inputJSON: String)? {
        if case .toolUse(let id, let name, let input) = self { return (id, name, input) }
        return nil
    }
}

struct AssistantMessage: Codable, Equatable, Identifiable {
    var id = UUID()
    var role: String            // "user" | "assistant"
    var blocks: [AssistantBlock]

    /// Messages API JSON.
    var wire: [String: Any] {
        var content: [[String: Any]] = []
        for block in blocks {
            switch block {
            case .text(let text):
                content.append(["type": "text", "text": text])
            case .toolUse(let id, let name, let inputJSON):
                let input = (try? JSONSerialization.jsonObject(with: Data(inputJSON.utf8))) ?? [:]
                content.append(["type": "tool_use", "id": id, "name": name, "input": input])
            case .toolResult(let id, let contentText, let isError):
                var result: [String: Any] = ["type": "tool_result", "tool_use_id": id,
                                             "content": contentText]
                if isError { result["is_error"] = true }
                content.append(result)
            }
        }
        return ["role": role, "content": content]
    }

    var plainText: String {
        blocks.compactMap { if case .text(let text) = $0 { return text } else { return nil } }
            .joined(separator: "\n")
    }
}

// MARK: - Key storage (Keychain, xcconfig fallback)

enum AssistantSecrets {
    private static let service = "OKTO.SAMp.HoopwiseMac.assistant"
    private static let account = "anthropic-api-key"

    static var apiKey: String? {
        if let stored = readKeychain(), !stored.isEmpty { return stored }
        // Fallback: the Assistant Coach build-time key, if present.
        if let plist = Bundle.main.object(forInfoDictionaryKey: "ANTHROPIC_API_KEY") as? String,
           !plist.isEmpty { return plist }
        return nil
    }

    static func setAPIKey(_ key: String) {
        deleteKeychain()
        guard !key.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(key.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static var hasStoredKey: Bool { readKeychain()?.isEmpty == false }

    private static func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Transport

/// The engine talks to a transport, not to Anthropic directly — DEBUG runs
/// can substitute a scripted transport to exercise the full chat/tool/confirm
/// path without a key or network.
protocol AssistantTransport {
    func streamTurn(system: [[String: Any]],
                    messages: [AssistantMessage],
                    tools: [[String: Any]],
                    model: String,
                    onTextDelta: @escaping @MainActor (String) -> Void)
        async throws -> (blocks: [AssistantBlock], stopReason: String)
}

enum AnthropicClientError: LocalizedError {
    case noAPIKey
    case httpError(Int, String)
    case badStream(String)

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No Anthropic API key. Add one in Settings → Assistant."
        case .httpError(let status, let message):
            return "Anthropic API error \(status): \(message)"
        case .badStream(let detail):
            return "Stream error: \(detail)"
        }
    }
}

/// Raw Messages API client over URLSession (no official Swift SDK) —
/// streaming SSE with tool use.
struct AnthropicClient: AssistantTransport {

    func streamTurn(system: [[String: Any]],
                    messages: [AssistantMessage],
                    tools: [[String: Any]],
                    model: String,
                    onTextDelta: @escaping @MainActor (String) -> Void)
        async throws -> (blocks: [AssistantBlock], stopReason: String)
    {
        guard let apiKey = AssistantSecrets.apiKey else { throw AnthropicClientError.noAPIKey }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "stream": true,
            "system": system,
            "messages": messages.map(\.wire),
        ]
        if !tools.isEmpty { body["tools"] = tools }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines { errorBody += line }
            let message = (try? JSONSerialization.jsonObject(with: Data(errorBody.utf8)) as? [String: Any])
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String } ?? errorBody
            throw AnthropicClientError.httpError(http.statusCode, message)
        }

        var blocks: [AssistantBlock] = []
        var stopReason = "end_turn"
        // Per-index accumulators for the current content block.
        var currentText = ""
        var currentToolId = ""
        var currentToolName = ""
        var currentToolJSON = ""
        var currentType = ""

        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }

            switch type {
            case "content_block_start":
                let block = event["content_block"] as? [String: Any] ?? [:]
                currentType = block["type"] as? String ?? ""
                currentText = ""
                currentToolJSON = ""
                if currentType == "tool_use" {
                    currentToolId = block["id"] as? String ?? UUID().uuidString
                    currentToolName = block["name"] as? String ?? ""
                }
            case "content_block_delta":
                let delta = event["delta"] as? [String: Any] ?? [:]
                switch delta["type"] as? String {
                case "text_delta":
                    let text = delta["text"] as? String ?? ""
                    currentText += text
                    await onTextDelta(text)
                case "input_json_delta":
                    currentToolJSON += delta["partial_json"] as? String ?? ""
                default:
                    break   // thinking deltas etc. — not surfaced
                }
            case "content_block_stop":
                switch currentType {
                case "text" where !currentText.isEmpty:
                    blocks.append(.text(currentText))
                case "tool_use":
                    blocks.append(.toolUse(id: currentToolId, name: currentToolName,
                                           inputJSON: currentToolJSON.isEmpty ? "{}" : currentToolJSON))
                default:
                    break
                }
                currentType = ""
            case "message_delta":
                if let delta = event["delta"] as? [String: Any],
                   let reason = delta["stop_reason"] as? String {
                    stopReason = reason
                }
            case "message_stop":
                return (blocks, stopReason)
            case "error":
                let error = event["error"] as? [String: Any]
                throw AnthropicClientError.badStream(error?["message"] as? String ?? "unknown")
            default:
                break
            }
        }
        return (blocks, stopReason)
    }

    /// Single non-streaming request for the cheap curation pass. Returns the
    /// concatenated text content.
    static func completeOnce(system: String, user: String, model: String,
                             maxTokens: Int = 1024) async throws -> String {
        guard let apiKey = AssistantSecrets.apiKey else { throw AnthropicClientError.noAPIKey }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]],
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let message = String(data: data, encoding: .utf8) ?? ""
            throw AnthropicClientError.httpError(status, message)
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = object["content"] as? [[String: Any]] else {
            throw AnthropicClientError.badStream("unparseable response")
        }
        return content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined()
    }
}

#if DEBUG
/// Scripted transport: exercises streaming text, a read tool call, and a
/// write tool call (which the engine turns into a confirmation card) without
/// network or key. Driven by HOOPWISE_DEMO_ASSISTANT=script.
struct ScriptedTransport: AssistantTransport {
    func streamTurn(system: [[String: Any]],
                    messages: [AssistantMessage],
                    tools: [[String: Any]],
                    model: String,
                    onTextDelta: @escaping @MainActor (String) -> Void)
        async throws -> (blocks: [AssistantBlock], stopReason: String)
    {
        let toolResultCount = messages.flatMap(\.blocks).filter {
            if case .toolResult = $0 { return true }; return false
        }.count

        func type(_ text: String) async {
            for word in text.split(separator: " ", omittingEmptySubsequences: false) {
                await onTextDelta(String(word) + " ")
                try? await Task.sleep(nanoseconds: 18_000_000)
            }
        }

        switch toolResultCount {
        case 0:
            await type("Let me check the roster first.")
            return ([.text("Let me check the roster first."),
                     .toolUse(id: "demo_tool_1", name: "search_athletes",
                              inputJSON: #"{"query": "cai"}"#)], "tool_use")
        case 1:
            await type("Found them. I'll schedule the session now — this needs your confirmation.")
            let input = """
            {"title": "Private · Demo Session", "starts": "2099-01-01T09:00:00+08:00", \
            "duration_minutes": 90, "location": "Hezhuang court"}
            """
            return ([.text("Found them. I'll schedule the session now — this needs your confirmation."),
                     .toolUse(id: "demo_tool_2", name: "create_session", inputJSON: input)], "tool_use")
        default:
            await type("Done — the session is on the calendar for Jan 1, 9:00 at Hezhuang court. ⌘Z undoes it.")
            return ([.text("Done — the session is on the calendar for Jan 1, 9:00 at Hezhuang court. ⌘Z undoes it.")],
                    "end_turn")
        }
    }
}
#endif
