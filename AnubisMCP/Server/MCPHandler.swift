import Foundation

/// MCP streamable-HTTP JSON-RPC handler — the subset the anubis client stack
/// (fastmcp / langchain_mcp_adapters streamable_http) exercises:
/// initialize, notifications/*, ping, tools/list, tools/call.
/// Responses are plain application/json (spec-legal alternative to SSE).
final class MCPHandler {
    struct Response {
        let status: Int
        let headers: [String: String]
        let body: Data
    }

    static let protocolVersion = "2025-03-26"
    private let registry: ToolRegistry
    private let serverName: String

    init(registry: ToolRegistry, serverName: String) {
        self.registry = registry
        self.serverName = serverName
    }

    func handlePost(body: Data, sessionID: String?) async -> Response {
        guard let message = JSON.decodeObject(body) else {
            return jsonResponse(status: 400, object: errorObject(id: NSNull(), code: -32700, message: "Parse error"))
        }

        let method = message["method"] as? String ?? ""
        let id = message["id"]

        // Notifications (no id) get 202 Accepted with no body.
        guard let requestID = id else {
            appLog("MCP notification: \(method)")
            return Response(status: 202, headers: [:], body: Data())
        }

        appLog("MCP request: \(method)")
        switch method {
        case "initialize":
            let params = message["params"] as? [String: Any] ?? [:]
            let requestedVersion = params["protocolVersion"] as? String ?? Self.protocolVersion
            let result: [String: Any] = [
                "protocolVersion": requestedVersion,
                "capabilities": ["tools": [:] as [String: Any]],
                "serverInfo": ["name": serverName, "version": "0.1.0"],
                "instructions": "MCP server running natively on an iPhone. Tools launch apps, drive the in-app browser, run Siri Shortcuts, and read/write phone data on the user's behalf.",
            ]
            let newSession = sessionID ?? UUID().uuidString
            return jsonResponse(
                status: 200,
                object: resultObject(id: requestID, result: result),
                extraHeaders: ["Mcp-Session-Id": newSession]
            )

        case "ping":
            return jsonResponse(status: 200, object: resultObject(id: requestID, result: [:]))

        case "tools/list":
            let result: [String: Any] = ["tools": registry.tools.map { $0.listEntry }]
            return jsonResponse(status: 200, object: resultObject(id: requestID, result: result))

        case "tools/call":
            let params = message["params"] as? [String: Any] ?? [:]
            guard let name = params["name"] as? String else {
                return jsonResponse(
                    status: 200,
                    object: errorObject(id: requestID, code: -32602, message: "Missing tool name"))
            }
            guard let tool = registry.tool(named: name) else {
                return jsonResponse(
                    status: 200,
                    object: errorObject(id: requestID, code: -32602, message: "Unknown tool: \(name)"))
            }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            do {
                let contents = try await tool.handler(arguments)
                let result: [String: Any] = [
                    "content": contents.map { $0.jsonObject },
                    "isError": false,
                ]
                return jsonResponse(status: 200, object: resultObject(id: requestID, result: result))
            } catch let error as ToolError {
                appLog("Tool \(name) error: \(error.message)")
                let result: [String: Any] = [
                    "content": [["type": "text", "text": error.message]],
                    "isError": true,
                ]
                return jsonResponse(status: 200, object: resultObject(id: requestID, result: result))
            } catch {
                appLog("Tool \(name) error: \(error.localizedDescription)")
                let result: [String: Any] = [
                    "content": [["type": "text", "text": "Tool failed: \(error.localizedDescription)"]],
                    "isError": true,
                ]
                return jsonResponse(status: 200, object: resultObject(id: requestID, result: result))
            }

        default:
            return jsonResponse(
                status: 200,
                object: errorObject(id: requestID, code: -32601, message: "Method not found: \(method)"))
        }
    }

    private func resultObject(id: Any, result: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private func errorObject(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private func jsonResponse(
        status: Int, object: [String: Any], extraHeaders: [String: String] = [:]
    ) -> Response {
        var headers = ["Content-Type": "application/json"]
        headers.merge(extraHeaders) { _, new in new }
        return Response(status: status, headers: headers, body: JSON.encode(object))
    }
}
