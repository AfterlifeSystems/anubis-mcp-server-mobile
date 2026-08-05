import Foundation

/// Port of the desktop daemon's ApiRegistrar: push-based presence over HTTPS
/// with the user's API key — POST /mcp/register, 30s /mcp/heartbeat loop, and
/// /mcp/unregister on shutdown.
///
/// Additive to the desktop wire contract: register/heartbeat also carry the
/// APNs push token and environment so the API can send a silent wake push when
/// this device's relay socket is gone (see push-to-wake in ServerController).
/// The API may ignore these fields; the desktop daemon simply never sends them.
actor Registrar {
    static let heartbeatIntervalSeconds: UInt64 = 30

    private let config: DeviceConfig
    private let apiKey: String
    private let session: URLSession
    private var heartbeatTask: Task<Void, Never>?
    private var pushToken: String?

    init(config: DeviceConfig, apiKey: String) {
        self.config = config
        self.apiKey = apiKey
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        session = URLSession(configuration: configuration)
    }

    /// Record the APNs token without hitting the network (used before the first
    /// register call).
    func setPushToken(_ token: String) {
        pushToken = token
    }

    /// Record a token that arrived after registration and re-register so the API
    /// learns how to wake this device.
    func updatePushToken(_ token: String) async {
        guard pushToken != token else { return }
        pushToken = token
        await register()
    }

    private func pushFields() -> [String: Any] {
        guard let pushToken else { return [:] }
        return [
            "platform": "ios",
            "apns_token": pushToken,
            "push_environment": config.pushEnvironment,
        ]
    }

    func register() async {
        var payload: [String: Any] = [
            "connection_mode": "relay",
            "server_name": config.serverName,
            "transport": "relay",
            "mcp_url": config.relayBridgeURL,
            "allowed_roots": config.allowedRoots,
            "device_secret": config.deviceSecret,
            "device_id": config.deviceID,
        ]
        payload.merge(pushFields()) { current, _ in current }
        do {
            let status = try await post(path: "/mcp/register", payload: payload)
            appLog("POST /mcp/register -> \(status)\(pushToken == nil ? "" : " (with push token)")")
        } catch {
            appLog("POST /mcp/register failed: \(error.localizedDescription)")
        }
    }

    func startHeartbeat() {
        guard heartbeatTask == nil else { return }
        heartbeatTask = Task {
            while !Task.isCancelled {
                do {
                    var payload: [String: Any] = [
                        "device_id": self.config.deviceID,
                        "mcp_url": self.config.relayBridgeURL,
                        "connection_mode": "relay",
                    ]
                    payload.merge(self.pushFields()) { current, _ in current }
                    let status = try await self.post(path: "/mcp/heartbeat", payload: payload)
                    if status >= 300 {
                        appLog("Heartbeat returned \(status)")
                    }
                } catch {
                    appLog("Heartbeat failed: \(error.localizedDescription)")
                }
                try? await Task.sleep(nanoseconds: Self.heartbeatIntervalSeconds * 1_000_000_000)
            }
        }
    }

    func stop() async {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        _ = try? await post(path: "/mcp/unregister", payload: ["device_id": config.deviceID])
    }

    private func post(path: String, payload: [String: Any]) async throws -> Int {
        guard let url = URL(string: config.apiBaseURL + path) else {
            throw ToolError("Bad API URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "API-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = JSON.encode(payload)
        let (_, response) = try await session.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }
}
