import Foundation

/// Bridge into the user's Shortcuts automations — the Apple-sanctioned way to
/// drive actions across other apps (ordering food, controlling home devices,
/// sending payments) from a published app. The user builds a shortcut once in
/// the Shortcuts app; the avatar can then run it by name with optional input.
enum ShortcutsTools {
    static func all() -> [MCPTool] {
        [runShortcut]
    }

    static let runShortcut = MCPTool(
        name: "run_shortcut",
        description: "Run one of the user's Siri Shortcuts by exact name, optionally passing text input. Shortcuts can perform multi-step actions in other apps (order food, message groups, control smart home). The Shortcuts app opens to execute it.",
        inputSchema: Schema.object(
            [
                "name": Schema.string("Exact name of the shortcut as it appears in the Shortcuts app"),
                "input": Schema.string("Optional text passed to the shortcut as its input"),
            ],
            required: ["name"]
        )
    ) { args in
        guard let name = args["name"] as? String else { throw ToolError("Missing 'name' argument") }
        var components = URLComponents(string: "shortcuts://run-shortcut")!
        var items = [URLQueryItem(name: "name", value: name)]
        if let input = args["input"] as? String, !input.isEmpty {
            items.append(URLQueryItem(name: "input", value: "text"))
            items.append(URLQueryItem(name: "text", value: input))
        }
        components.queryItems = items
        guard let url = components.url else { throw ToolError("Could not build shortcut URL") }
        return try await AppLaunchTools.open(urlString: url.absoluteString, label: "Shortcut '\(name)'")
    }
}
