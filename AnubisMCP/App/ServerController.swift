import Foundation
import SwiftUI
import UIKit

/// Orchestrates the whole daemon inside the app: local MCP server, outbound
/// relay, and API registration — the iOS equivalent of the desktop daemon's
/// __main__ start sequence. Restarts the relay when the app returns to the
/// foreground, and — the push-to-wake path — when a silent APNs push arrives
/// while the app is suspended in the background (iOS tears down sockets there).
@MainActor
final class ServerController: ObservableObject {
    /// Shared instance so the UIApplicationDelegate (push callbacks) and the
    /// SwiftUI scene drive the same controller.
    static let shared = ServerController()

    @Published private(set) var relayState: OutboundRelay.State = .disconnected
    @Published private(set) var serverRunning = false
    @Published private(set) var config: DeviceConfig
    @Published var hasAPIKey: Bool
    @Published private(set) var pushToken: String?

    let browser: BrowserAutomator

    private var httpServer: HTTPServerService?
    private var relay: OutboundRelay?
    private var registrar: Registrar?

    /// Last time the relay tunneled a request to the local server. Used by the
    /// wake window to stay alive while requests are actively flowing and finish
    /// promptly once the avatar goes idle.
    private var lastProxyActivity = Date.distantPast
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    private init() {
        config = DeviceConfig.load()
        hasAPIKey = Credentials.apiKey() != nil
        browser = BrowserAutomator()

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.restartRelayIfNeeded() }
        }
    }

    func start() {
        // Keep the screen (and therefore the app + relay socket) alive while the
        // app is frontmost. Background presence is handled by push-to-wake.
        UIApplication.shared.isIdleTimerDisabled = true

        if httpServer == nil {
            let registry = ToolRegistry(browser: browser)
            let handler = MCPHandler(registry: registry, serverName: config.serverName)
            let server = HTTPServerService(config: config, handler: handler)
            server.start()
            httpServer = server
            serverRunning = true
        }
        startRelay()

        // Test hook: exercise the exact push/URL wake code path deterministically
        // in the simulator, where silent pushes are not delivered to the
        // background handler. Never set in production.
        if ProcessInfo.processInfo.environment["ANUBIS_WAKE_TEST"] == "1" {
            Task {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                self.wake(reason: "launch-test")
            }
        }
    }

    func saveAPIKey(_ key: String) {
        Credentials.saveAPIKey(key)
        hasAPIKey = Credentials.apiKey() != nil
        Task { await teardownRelay(); startRelay() }
    }

    // MARK: - Push-to-wake

    /// APNs device token arrived. Store it and (re)register so the API can send
    /// this device a silent wake push when its relay socket is gone.
    func updatePushToken(_ token: String) {
        pushToken = token
        Task {
            await registrar?.updatePushToken(token)
        }
    }

    /// Bring the relay back up and hold a background-task assertion open through
    /// the ~30s execution window so a tunneled request can be serviced, then
    /// report whether any request actually arrived.
    ///
    /// Driven by a silent (`content-available`) APNs push in production
    /// (`reason: "apns-silent-push"`), and reachable via the `anubismcp://wake`
    /// URL / App Intent so the wake path can also be triggered by a Shortcut or
    /// exercised in the simulator, where `simctl` does not deliver silent pushes
    /// to the background handler.
    func wake(reason: String, completion: ((Bool) -> Void)? = nil) {
        appLog("Wake triggered (\(reason))")
        beginBackgroundAssertion()
        lastProxyActivity = Date()

        if relay == nil {
            startRelay()
        } else {
            // A stale socket may look alive after suspension; recycle it.
            Task { await teardownRelay(); startRelay() }
        }

        Task {
            let hadActivity = await waitForWakeWindow()
            endBackgroundAssertion()
            appLog("Wake window closed (serviced request: \(hadActivity))")
            completion?(hadActivity)
        }
    }

    private func waitForWakeWindow() async -> Bool {
        let start = Date()
        let wakeMoment = lastProxyActivity

        // Wait for the relay to register (up to 12s of the budget).
        while relayState != .registered, Date().timeIntervalSince(start) < 12 {
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        // Stay alive while proxy traffic is flowing; finish after 5s of quiet or
        // at the 25s ceiling — safely inside the OS background window.
        while Date().timeIntervalSince(start) < 25 {
            let idle = Date().timeIntervalSince(lastProxyActivity)
            if relayState == .registered, idle > 5 { break }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
        return lastProxyActivity > wakeMoment
    }

    private func beginBackgroundAssertion() {
        endBackgroundAssertion()
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "anubis-relay-wake") {
            [weak self] in
            self?.endBackgroundAssertion()
        }
    }

    private func endBackgroundAssertion() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    // MARK: - Relay lifecycle

    private func startRelay() {
        guard relay == nil else { return }
        guard let apiKey = Credentials.apiKey() else {
            appLog("No API key configured; relay idle. Enter an sk-... key to connect.")
            return
        }
        let relay = OutboundRelay(
            config: config,
            apiKey: apiKey,
            onState: { [weak self] state in
                Task { @MainActor in
                    self?.relayState = state
                    appLog("Relay state: \(state.rawValue)")
                }
            },
            onActivity: { [weak self] in
                Task { @MainActor in self?.lastProxyActivity = Date() }
            }
        )
        self.relay = relay
        Task { await relay.start() }

        let registrar = Registrar(config: config, apiKey: apiKey)
        self.registrar = registrar
        let token = pushToken
        Task {
            if let token { await registrar.setPushToken(token) }
            await registrar.register()
            await registrar.startHeartbeat()
        }
    }

    private func teardownRelay() async {
        if let relay { await relay.stop() }
        relay = nil
        if let registrar { await registrar.stop() }
        registrar = nil
    }

    private func restartRelayIfNeeded() {
        guard hasAPIKey else { return }
        appLog("Foregrounded; ensuring relay is alive")
        Task {
            await teardownRelay()
            startRelay()
        }
    }
}
