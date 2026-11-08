import Foundation
import Network

#if targetEnvironment(macCatalyst)
// MARK: - Claude Desktop connector: the server (Mac only, November 2026)
//
// The Mac app listens on 127.0.0.1 ONLY (never the network) and speaks MCP
// (JSON-RPC 2.0 over HTTP POST) to a tiny bridge script that Claude Desktop
// launches as a local "stdio" server:
//
//   Claude Desktop ⇄ stdin/stdout ⇄ hoopwise-connector.py ⇄ HTTP 127.0.0.1 ⇄ this
//
// Every request must carry the random access key (Authorization: Bearer …),
// generated once per Mac, so another program cannot drive the app without
// it. The app is SANDBOXED (Mac App Store): it may listen only because of
// ENABLE_INCOMING_NETWORK_CONNECTIONS, and it cannot write anywhere Claude
// Desktop reads. So the bridge is a fixed script kept outside the app
// (tools/claude-connector/hoopwise-connector.py) and Claude Desktop's own
// config hands it the address and key as environment variables — the
// coach copies that config from Profile → Claude Desktop.
// The tools themselves are ConnectorToolRegistry. The app must be running
// for Claude to reach it; the bridge says so when it is not.

@MainActor
final class ConnectorServer {
    static let shared = ConnectorServer()
    /// 47720. DEBUG: HOOPWISE_CONNECTOR_PORT lets a demo copy listen beside
    /// the coach's running app, so verifying the tools never means quitting it.
    static let port: UInt16 = {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["HOOPWISE_CONNECTOR_PORT"], let forced = UInt16(raw) { return forced }
        #endif
        return 47720
    }()

    private var listener: NWListener?
    private(set) var isListening = false
    private var registry: ConnectorToolRegistry?
    private let queue = DispatchQueue(label: "hoopwise.connector")

    private init() {}

    /// Starts listening and writes the bridge + its settings. Idempotent.
    func start(dataManager: DataManager) {
        guard listener == nil else { return }
        registry = ConnectorToolRegistry(dataManager: dataManager)
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1",
                                                         port: NWEndpoint.Port(rawValue: Self.port)!)
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.serve(connection) }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isListening = true
                        macPopupTrace("connector listening on 127.0.0.1:\(Self.port)")
                    case .failed(let error):
                        self?.isListening = false
                        macPopupTrace("connector failed: \(error)")
                    default: break
                    }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            macPopupTrace("connector could not start: \(error)")
        }
    }

    /// The access key, generated once per Mac.
    static var token: String {
        #if DEBUG
        // Agent/test runs: a known key without reading the sandboxed defaults.
        if let forced = ProcessInfo.processInfo.environment["HOOPWISE_CONNECTOR_TOKEN"] { return forced }
        #endif
        let key = "connector.token"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let fresh = (0..<4).map { _ in UUID().uuidString.replacingOccurrences(of: "-", with: "") }.joined()
        UserDefaults.standard.set(fresh, forKey: key)
        return fresh
    }

    // MARK: - HTTP

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private nonisolated func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = HTTPRequest(buffer) {
                Task { @MainActor in
                    let response = self?.respond(to: request) ?? HTTPRequest.response(status: 500, body: Data())
                    connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
                }
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self?.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: HTTPRequest) -> Data {
        guard request.authorization == "Bearer \(Self.token)" else {
            return HTTPRequest.response(status: 401, body: Data("unauthorized".utf8))
        }
        guard let message = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            return HTTPRequest.response(status: 400, body: Data("not JSON".utf8))
        }
        guard let reply = handle(message) else {
            return HTTPRequest.response(status: 202, body: Data())   // a notification
        }
        let body = (try? JSONSerialization.data(withJSONObject: reply)) ?? Data()
        return HTTPRequest.response(status: 200, body: body, contentType: "application/json")
    }

    // MARK: - MCP (JSON-RPC 2.0)

    private func handle(_ message: [String: Any]) -> [String: Any]? {
        let method = message["method"] as? String ?? ""
        guard let id = message["id"] else { return nil }   // notifications get no reply
        func result(_ value: Any) -> [String: Any] { ["jsonrpc": "2.0", "id": id, "result": value] }
        func failure(_ code: Int, _ text: String) -> [String: Any] {
            ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": text]]
        }
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return result([
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "hoopwise", "version": "1.0"],
                "instructions": """
                Hoopwise is a basketball coach's app. Find people with search_athletes and classes \
                with list_sessions before acting, and pass the short refs they return (8 characters) \
                as athlete_id / session_id — a session can also be named by when (its start) plus \
                program. Names may be Chinese, pinyin or English. To put someone in ONE class use \
                add_to_session; to make them a regular of a program use add_to_program (set_enrollment \
                MOVES them out of every other class; remove_from_program takes them off ONE). School grades \
                go in school_grade, not notes. \
                A private lesson shared by several clients is ONE session with every client on the roster \
                (each is charged from their own bundle) — never one session per client. What a session worked \
                on goes in the SESSION's notes (create_session / update_session notes), not in record_note, \
                which is an athlete's contact log. Check create_session's returned roster: anyone expected \
                and left unmarked once roll call starts is inferred absent and charged. \
                Writes go through the app's own rules and are refused when a rule says no — relay \
                the reason. To put things right: list_charges (what was charged), refund_session, \
                skip_session / reopen_session / complete_session, delete_session (refunds, but removes marks \
                and notes for good), delete_athlete_note, remove_play_from_session, delete_play*. Before a \
                delete, say what will be lost. Athletes, contracts and payments are never deleted here.
                PLAYS: the coach's play library (Hub → Plays). Before creating or changing a play call                 get_play_drawing_guide, and read a similar play with get_play to see the format filled in.                 create_play saves a whole play (steps, wrinkles, variations) after checking every field;                 read it back with get_play. add_play_to_session puts a play in a session's plan.
                """,
            ])
        case "ping":
            return result([:])
        case "tools/list":
            let tools = (registry?.tools ?? []).map { tool -> [String: Any] in
                ["name": tool.name,
                 "description": tool.description,
                 "inputSchema": tool.schema,
                 "annotations": ["readOnlyHint": !tool.category.isWrite,
                                 "destructiveHint": tool.destructive]]
            }
            return result(["tools": tools])
        case "tools/call":
            guard let name = params["name"] as? String, let registry else {
                return failure(-32602, "tool name missing")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let json = (try? JSONSerialization.data(withJSONObject: arguments))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            let outcome = registry.execute(name: name, argumentsJSON: json)
            macPopupTrace("connector \(name): \(outcome.summary)")
            return result(["content": [["type": "text", "text": outcome.payload]],
                           "isError": outcome.isError])
        default:
            return failure(-32601, "method not found: \(method)")
        }
    }
}

/// Just enough HTTP/1.1 for one POST per connection.
private struct HTTPRequest {
    let authorization: String?
    let body: Data

    /// nil until the headers and the whole body have arrived.
    init?(_ data: Data) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        var headers: [String: String] = [:]
        for line in head.components(separatedBy: "\r\n").dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count - bodyStart >= length else { return nil }
        authorization = headers["authorization"]
        body = data[bodyStart..<(bodyStart + length)]
    }

    static func response(status: Int, body: Data, contentType: String = "text/plain") -> Data {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized"][status] ?? "Error"
        var head = "HTTP/1.1 \(status) \(reason)\r\nContent-Length: \(body.count)\r\n"
        head += "Content-Type: \(contentType)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}

/// What Profile → Claude Desktop copies: the entry for Claude Desktop's
/// claude_desktop_config.json.
enum ConnectorSetup {
    /// Where the bridge is installed (outside the sandbox, by the setup).
    static let bridgePath = "~/Library/Application Support/Hoopwise Connector/hoopwise-connector.py"

    static var isListening: Bool { ConnectorServer.shared.isListening }

    static func claudeDesktopConfig() -> String {
        let home = NSHomeDirectory().components(separatedBy: "/Library/Containers/").first ?? NSHomeDirectory()
        let entry: [String: Any] = ["mcpServers": ["hoopwise": [
            "command": "/usr/bin/python3",
            "args": [bridgePath.replacingOccurrences(of: "~", with: home)],
            "env": ["HOOPWISE_URL": "http://127.0.0.1:\(ConnectorServer.port)/mcp",
                    "HOOPWISE_TOKEN": ConnectorServer.token],
        ]]]
        let data = (try? JSONSerialization.data(withJSONObject: entry, options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
#endif
