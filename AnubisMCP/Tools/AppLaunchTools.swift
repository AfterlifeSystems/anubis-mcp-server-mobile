import Foundation
import UIKit

/// "App use" on a sandboxed, publishable iOS app: launching and deep-linking
/// into other installed apps via their URL schemes. The curated registry
/// covers common tasks (food ordering, rides, maps, media, payments); any
/// other app can be reached with open_url and its documented scheme.
enum AppLaunchTools {
    struct KnownApp {
        let key: String
        let displayName: String
        let scheme: String
        let example: String
    }

    static let knownApps: [KnownApp] = [
        KnownApp(key: "maps", displayName: "Apple Maps", scheme: "maps://", example: "maps://?q=pizza+near+me"),
        KnownApp(key: "google_maps", displayName: "Google Maps", scheme: "comgooglemaps://", example: "comgooglemaps://?q=pizza"),
        KnownApp(key: "safari", displayName: "Safari", scheme: "https://", example: "https://www.example.com"),
        KnownApp(key: "shortcuts", displayName: "Shortcuts", scheme: "shortcuts://", example: "shortcuts://run-shortcut?name=Order%20Lunch"),
        KnownApp(key: "photos", displayName: "Photos", scheme: "photos-redirect://", example: "photos-redirect://"),
        KnownApp(key: "music", displayName: "Apple Music", scheme: "music://", example: "music://"),
        KnownApp(key: "facetime", displayName: "FaceTime", scheme: "facetime://", example: "facetime://user@example.com"),
        KnownApp(key: "doordash", displayName: "DoorDash", scheme: "doordash://", example: "doordash://store/12345"),
        KnownApp(key: "ubereats", displayName: "Uber Eats", scheme: "ubereats://", example: "ubereats://"),
        KnownApp(key: "grubhub", displayName: "Grubhub", scheme: "grubhub://", example: "grubhub://"),
        KnownApp(key: "postmates", displayName: "Postmates", scheme: "postmates://", example: "postmates://"),
        KnownApp(key: "yelp", displayName: "Yelp", scheme: "yelp://", example: "yelp:///search?terms=ramen"),
        KnownApp(key: "opentable", displayName: "OpenTable", scheme: "opentable://", example: "opentable://"),
        KnownApp(key: "resy", displayName: "Resy", scheme: "resy://", example: "resy://"),
        KnownApp(key: "uber", displayName: "Uber", scheme: "uber://", example: "uber://?action=setPickup"),
        KnownApp(key: "lyft", displayName: "Lyft", scheme: "lyft://", example: "lyft://ridetype?id=lyft"),
        KnownApp(key: "spotify", displayName: "Spotify", scheme: "spotify://", example: "spotify://search/beatles"),
        KnownApp(key: "youtube", displayName: "YouTube", scheme: "youtube://", example: "youtube://results?search_query=query"),
        KnownApp(key: "instagram", displayName: "Instagram", scheme: "instagram://", example: "instagram://user?username=name"),
        KnownApp(key: "twitter", displayName: "X (Twitter)", scheme: "twitter://", example: "twitter://search?query=term"),
        KnownApp(key: "whatsapp", displayName: "WhatsApp", scheme: "whatsapp://", example: "whatsapp://send?text=hello"),
        KnownApp(key: "venmo", displayName: "Venmo", scheme: "venmo://", example: "venmo://paycharge?txn=pay"),
        KnownApp(key: "paypal", displayName: "PayPal", scheme: "paypal://", example: "paypal://"),
        KnownApp(key: "amazon", displayName: "Amazon", scheme: "amazon://", example: "amazon://apps/android?p=query"),
        KnownApp(key: "walmart", displayName: "Walmart", scheme: "walmart://", example: "walmart://"),
        KnownApp(key: "settings", displayName: "Settings (this app's page)", scheme: UIApplication.openSettingsURLString, example: UIApplication.openSettingsURLString),
    ]

    static func all() -> [MCPTool] {
        [listApps, openApp, openURL]
    }

    static let listApps = MCPTool(
        name: "list_apps",
        description: "List known launchable apps and whether each is installed on this phone. Use before open_app.",
        inputSchema: Schema.object([:])
    ) { _ in
        let entries: [[String: Any]] = await MainActor.run {
            knownApps.map { app in
                let installed = URL(string: app.scheme).map {
                    UIApplication.shared.canOpenURL($0)
                } ?? false
                return [
                    "app": app.key,
                    "name": app.displayName,
                    "installed": installed,
                    "deep_link_example": app.example,
                ]
            }
        }
        return [.text(JSON.encodeString(["apps": entries]))]
    }

    static let openApp = MCPTool(
        name: "open_app",
        description: "Open an installed app by key from list_apps, optionally with a full deep link URL to jump straight to content (e.g. a restaurant page or a search).",
        inputSchema: Schema.object(
            [
                "app": Schema.string("App key from list_apps, e.g. 'maps', 'doordash', 'yelp'"),
                "deep_link": Schema.string("Optional full deep-link URL using the app's scheme; overrides the plain launch"),
            ],
            required: ["app"]
        )
    ) { args in
        guard let key = args["app"] as? String else { throw ToolError("Missing 'app' argument") }
        guard let app = knownApps.first(where: { $0.key == key }) else {
            throw ToolError("Unknown app '\(key)'. Call list_apps for options, or use open_url with a custom scheme.")
        }
        let urlString = (args["deep_link"] as? String) ?? app.scheme
        return try await open(urlString: urlString, label: app.displayName)
    }

    static let openURL = MCPTool(
        name: "open_url",
        description: "Open any URL on the phone — https:// links open in Safari, custom schemes deep-link into their apps.",
        inputSchema: Schema.object(["url": Schema.string("The URL to open")], required: ["url"])
    ) { args in
        guard let urlString = args["url"] as? String else { throw ToolError("Missing 'url' argument") }
        return try await open(urlString: urlString, label: urlString)
    }

    static func open(urlString: String, label: String) async throws -> [ToolContent] {
        guard let url = URL(string: urlString) else { throw ToolError("Invalid URL: \(urlString)") }
        let opened = await MainActor.run { () -> Bool in
            guard UIApplication.shared.canOpenURL(url) else { return false }
            UIApplication.shared.open(url)
            return true
        }
        guard opened else {
            throw ToolError("Cannot open \(label): app not installed or scheme not allowed")
        }
        return [.text(JSON.encodeString(["ok": true, "opened": urlString]))]
    }
}
