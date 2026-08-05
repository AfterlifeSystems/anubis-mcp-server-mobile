import Foundation

/// One piece of MCP tool-call result content (text or base64 image).
enum ToolContent {
    case text(String)
    case image(base64: String, mimeType: String)

    var jsonObject: [String: Any] {
        switch self {
        case .text(let text):
            return ["type": "text", "text": text]
        case .image(let base64, let mimeType):
            return ["type": "image", "data": base64, "mimeType": mimeType]
        }
    }
}

struct ToolError: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

/// A single MCP tool: JSON schema plus async handler.
struct MCPTool {
    let name: String
    let description: String
    /// JSON Schema for the arguments object.
    let inputSchema: [String: Any]
    let handler: ([String: Any]) async throws -> [ToolContent]

    var listEntry: [String: Any] {
        [
            "name": name,
            "description": description,
            "inputSchema": inputSchema,
        ]
    }
}

/// Convenience for building `inputSchema` objects.
enum Schema {
    static func object(
        _ properties: [String: [String: Any]],
        required: [String] = []
    ) -> [String: Any] {
        var schema: [String: Any] = [
            "type": "object",
            "properties": properties,
        ]
        if !required.isEmpty { schema["required"] = required }
        return schema
    }

    static func string(_ description: String) -> [String: Any] {
        ["type": "string", "description": description]
    }

    static func integer(_ description: String) -> [String: Any] {
        ["type": "integer", "description": description]
    }

    static func boolean(_ description: String) -> [String: Any] {
        ["type": "boolean", "description": description]
    }
}

/// Registry of every tool the phone exposes to the avatar.
final class ToolRegistry {
    private(set) var tools: [MCPTool] = []

    init(browser: BrowserAutomator) {
        tools += DeviceTools.all()
        tools += AppLaunchTools.all()
        tools += ShortcutsTools.all()
        tools += CommsTools.all()
        tools += PIMTools.all()
        tools += LocationTools.all()
        tools += BrowserTools.all(browser: browser)
    }

    func tool(named name: String) -> MCPTool? {
        tools.first { $0.name == name }
    }
}
