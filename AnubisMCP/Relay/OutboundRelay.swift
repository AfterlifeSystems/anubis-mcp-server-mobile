import Foundation

/// Port of the desktop daemon's OutboundRelay (src/daemon/relay.py): one
/// outbound WebSocket to <api>/mcp/relay, register frame on connect, pong on
/// ping/heartbeat, and HTTP-over-WebSocket proxying of `proxy` frames against
/// the local MCP server. Frame names are a fixed contract with the anubis API.
actor OutboundRelay {
    enum State: String {
        case disconnected
        case connecting
        case connected
        case registered
    }

    private let config: DeviceConfig
    private let apiKey: String
    private let onState: @Sendable (State) -> Void
    private let onActivity: @Sendable () -> Void

    private var task: Task<Void, Never>?
    private var socket: URLSessionWebSocketTask?
    private let reconnectDelaySeconds: UInt64 = 5

    private let localHTTP: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        return URLSession(configuration: configuration)
    }()

    init(
        config: DeviceConfig,
        apiKey: String,
        onState: @escaping @Sendable (State) -> Void,
        onActivity: @escaping @Sendable () -> Void = {}
    ) {
        self.config = config
        self.apiKey = apiKey
        self.onState = onState
        self.onActivity = onActivity
    }

    func start() {
        guard task == nil else { return }
        task = Task { await runLoop() }
    }

    func stop() {
        task?.cancel()
        task = nil
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        onState(.disconnected)
    }

    private func runLoop() async {
        while !Task.isCancelled {
            onState(.connecting)
            do {
                try await connectAndListen()
            } catch {
                if !Task.isCancelled {
                    appLog("Relay connection failed (\(error.localizedDescription)); retrying in \(reconnectDelaySeconds)s")
                }
            }
            onState(.disconnected)
            if Task.isCancelled { break }
            try? await Task.sleep(nanoseconds: reconnectDelaySeconds * 1_000_000_000)
        }
    }

    private func connectAndListen() async throws {
        var request = URLRequest(url: config.relayWSURL)
        request.setValue(apiKey, forHTTPHeaderField: "API-KEY")
        let socket = URLSession.shared.webSocketTask(with: request)
        self.socket = socket
        socket.resume()

        try await send(registerFrame())
        appLog("Outbound relay connected to \(config.relayWSURL.absoluteString)")
        onState(.connected)

        let keepalive = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                socket.sendPing { _ in }
            }
        }
        defer { keepalive.cancel() }

        while !Task.isCancelled {
            let message = try await socket.receive()
            let text: String
            switch message {
            case .string(let string):
                text = string
            case .data(let data):
                text = String(data: data, encoding: .utf8) ?? ""
            @unknown default:
                continue
            }
            guard let frame = JSON.decodeObject(text) else {
                appLog("Ignoring non-JSON relay message")
                continue
            }
            try await handle(frame)
        }
    }

    private func registerFrame() -> [String: Any] {
        [
            "type": "register",
            "connection_mode": "relay",
            "device_id": config.deviceID,
            "device_secret": config.deviceSecret,
            "server_name": config.serverName,
            "transport": "streamable_http",
            "allowed_roots": config.allowedRoots,
            "local_mcp_url": config.localMCPURL,
        ]
    }

    private func handle(_ frame: [String: Any]) async throws {
        let type = frame["type"] as? String
        switch type {
        case "ping", "heartbeat":
            try await send(["type": "pong"])
        case "registered":
            appLog("API acknowledged relay registration for \(frame["device_id"] as? String ?? "?")")
            onState(.registered)
        case "proxy":
            onActivity()
            let response = await proxyToLocalMCP(frame)
            try await send(response)
        default:
            appLog("Unhandled relay frame type: \(type ?? "nil")")
        }
    }

    /// Replay one tunneled HTTP request against the local MCP server,
    /// mirroring _proxy_to_local_mcp in the desktop daemon.
    private func proxyToLocalMCP(_ frame: [String: Any]) async -> [String: Any] {
        let requestID = frame["request_id"] as? String ?? ""
        let method = (frame["method"] as? String ?? "POST").uppercased()
        let path = frame["path"] as? String ?? "/mcp"
        var headers = frame["headers"] as? [String: String] ?? [:]

        if headers["Authorization"] == nil && headers["authorization"] == nil {
            headers["Authorization"] = "Bearer \(config.deviceSecret)"
        }

        var bodyData: Data?
        if let body = frame["body"] {
            if let bodyString = body as? String {
                if frame["body_encoding"] as? String == "base64" {
                    bodyData = Data(base64Encoded: bodyString)
                } else {
                    bodyData = Data(bodyString.utf8)
                }
            } else if !(body is NSNull) {
                bodyData = JSON.encode(body)
            }
        }

        guard let url = URL(string: config.localProxyTargetURL + path) else {
            return proxyErrorResponse(requestID: requestID, message: "bad path \(path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = bodyData
        for (key, value) in headers {
            // URLSession owns hop-by-hop headers.
            if ["content-length", "host", "connection"].contains(key.lowercased()) { continue }
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let (data, response) = try await localHTTP.data(for: request)
            let http = response as? HTTPURLResponse
            var responseHeaders: [String: String] = [:]
            for (key, value) in http?.allHeaderFields ?? [:] {
                if let keyString = key as? String, let valueString = value as? String {
                    responseHeaders[keyString] = valueString
                }
            }
            let isText = String(data: data, encoding: .utf8) != nil
            return [
                "type": "proxy_response",
                "request_id": requestID,
                "status_code": http?.statusCode ?? 200,
                "headers": responseHeaders,
                "body": isText
                    ? String(data: data, encoding: .utf8)!
                    : data.base64EncodedString(),
                "body_encoding": isText ? "text" : "base64",
            ]
        } catch {
            appLog("Local MCP proxy failed for \(method) \(path): \(error.localizedDescription)")
            return proxyErrorResponse(requestID: requestID, message: error.localizedDescription)
        }
    }

    private func proxyErrorResponse(requestID: String, message: String) -> [String: Any] {
        [
            "type": "proxy_response",
            "request_id": requestID,
            "status_code": 502,
            "headers": ["content-type": "application/json"],
            "body": JSON.encodeString(["error": message]),
            "body_encoding": "text",
        ]
    }

    private func send(_ object: [String: Any]) async throws {
        guard let socket else { throw ToolError("Relay socket is not connected") }
        try await socket.send(.string(JSON.encodeString(object)))
    }
}
