import Foundation

/// Mirrors the desktop daemon's DaemonConfig: device identity, API base URL,
/// server name, and the local MCP port. Identity is generated once and kept
/// in the keychain, matching the `device_id` / `mcp_dev_...` scheme in
/// anubis-mcp-server-ubuntu-desktop's config.py.
struct DeviceConfig {
    static let defaultAPIBaseURL = "https://api.neuralnexus.site"
    static let mcpPath = "/mcp"

    let apiBaseURL: String
    let serverName: String
    let port: UInt16
    let deviceID: String
    let deviceSecret: String
    /// APNs environment this build's push token belongs to, so the API dials the
    /// right APNs endpoint for wake pushes. Debug builds use the sandbox.
    let pushEnvironment: String
    /// Not a filesystem server; announce a descriptive pseudo-root so the
    /// device shows up meaningfully in the avatar's device list.
    let allowedRoots = ["ios://app-use"]

    /// Advertised in the register frame (informational in relay mode — the API
    /// never dials it directly, it tunnels over the socket).
    var localMCPURL: String { "http://127.0.0.1:\(port)" }

    /// Target the in-process relay uses to replay tunneled requests against the
    /// embedded server. Uses `localhost` so it connects regardless of whether
    /// the server bound IPv4 (127.0.0.1) or IPv6 (::1) loopback.
    var localProxyTargetURL: String { "http://localhost:\(port)" }

    var relayWSURL: URL {
        var components = URLComponents(string: apiBaseURL)!
        components.scheme = components.scheme == "http" ? "ws" : "wss"
        components.path = "/mcp/relay"
        return components.url!
    }

    /// The API-side bridge URL registered as this device's mcp_url in relay mode.
    var relayBridgeURL: String { "\(apiBaseURL)/mcp/relay/\(deviceID)" }

    static func load() -> DeviceConfig {
        let env = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard

        let apiBaseURL = (env["ANUBIS_API_BASE_URL"]
            ?? defaults.string(forKey: "api_base_url")
            ?? defaultAPIBaseURL)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/ "))

        // Env overrides (used by simulator test runs) win over the keychain so
        // an external client can present a known bearer token; production
        // generates and persists these once.
        let deviceID: String
        if let override = env["ANUBIS_DEVICE_ID"], !override.isEmpty {
            deviceID = override
        } else if let existing = KeychainStore.get("device_id") {
            deviceID = existing
        } else {
            deviceID = randomToken(bytes: 12)
            KeychainStore.set("device_id", deviceID)
        }

        let deviceSecret: String
        if let override = env["ANUBIS_DEVICE_SECRET"], !override.isEmpty {
            deviceSecret = override
        } else if let existing = KeychainStore.get("device_secret") {
            deviceSecret = existing
        } else {
            deviceSecret = "mcp_dev_" + randomToken(bytes: 32)
            KeychainStore.set("device_secret", deviceSecret)
        }

        #if DEBUG
        let defaultPushEnv = "sandbox"
        #else
        let defaultPushEnv = "production"
        #endif

        return DeviceConfig(
            apiBaseURL: apiBaseURL,
            serverName: env["ANUBIS_SERVER_NAME"] ?? "iPhone-App-Use",
            port: UInt16(env["ANUBIS_MCP_PORT"] ?? "") ?? 8000,
            deviceID: deviceID,
            deviceSecret: deviceSecret,
            pushEnvironment: env["ANUBIS_PUSH_ENV"] ?? defaultPushEnv
        )
    }

    /// URL-safe base64 token, same shape as Python's secrets.token_urlsafe.
    private static func randomToken(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// API key (sk-...) storage. Launch environment wins so simulator test runs
/// never persist the key into the app container; otherwise the keychain copy
/// saved from the setup UI is used.
enum Credentials {
    static func apiKey() -> String? {
        if let key = ProcessInfo.processInfo.environment["ANUBIS_API_KEY"], !key.isEmpty {
            return key
        }
        return KeychainStore.get("api_key")
    }

    static func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.delete("api_key")
        } else {
            KeychainStore.set("api_key", trimmed)
        }
    }
}
