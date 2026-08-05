import AppIntents
import Foundation

/// App Intents surface: lets Siri and the Shortcuts app drive this app —
/// Apple's sanctioned automation channel. Complements run_shortcut (which
/// goes the other direction, app → user shortcuts).
struct AnubisStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Anubis MCP Status"
    static var description = IntentDescription("Reports whether the Anubis MCP relay is connected.")
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let hasKey = Credentials.apiKey() != nil
        let dialog = hasKey
            ? "Anubis MCP is configured. Open the app to keep the relay live."
            : "Anubis MCP has no API key yet. Open the app to add one."
        return .result(dialog: IntentDialog(stringLiteral: dialog))
    }
}

struct OpenAnubisIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Anubis Relay"
    static var description = IntentDescription("Opens Anubis MCP so the relay connects and the avatar can reach this phone.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct AnubisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenAnubisIntent(),
            phrases: ["Start \(.applicationName) relay"],
            shortTitle: "Start Relay",
            systemImageName: "antenna.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: AnubisStatusIntent(),
            phrases: ["\(.applicationName) status"],
            shortTitle: "Status",
            systemImageName: "info.circle"
        )
    }
}
