import FlyingFox
import Foundation

/// The embedded local MCP HTTP server, loopback-only (mirrors the desktop
/// daemon: never exposed to the network; reachable via the outbound relay).
final class HTTPServerService {
    private let config: DeviceConfig
    private let handler: MCPHandler
    private var server: HTTPServer?
    private var serverTask: Task<Void, Never>?

    init(config: DeviceConfig, handler: MCPHandler) {
        self.config = config
        self.handler = handler
    }

    func start() {
        guard serverTask == nil else { return }
        let server = HTTPServer(address: .loopback(port: config.port))
        self.server = server
        let config = self.config
        let handler = self.handler

        serverTask = Task {
            await server.appendRoute("GET /health") { _ in
                let body = JSON.encode([
                    "status": "ok",
                    "server_name": config.serverName,
                    "allowed_roots": config.allowedRoots,
                ])
                return HTTPResponse(
                    statusCode: .ok,
                    headers: [.contentType: "application/json"],
                    body: body
                )
            }

            await server.appendRoute("GET /mcp") { _ in
                HTTPResponse(statusCode: HTTPStatusCode(405, phrase: "Method Not Allowed"))
            }

            await server.appendRoute("DELETE /mcp") { _ in
                HTTPResponse(statusCode: .ok)
            }

            await server.appendRoute("POST /mcp") { request in
                let authorization = request.headers[.authorization] ?? ""
                let expected = "Bearer \(config.deviceSecret)"
                guard authorization == expected else {
                    appLog("MCP request rejected: bad bearer token")
                    let body = JSON.encode(["error": "invalid_token"])
                    return HTTPResponse(
                        statusCode: .unauthorized,
                        headers: [.contentType: "application/json"],
                        body: body
                    )
                }
                let body = try await request.bodyData
                let sessionID = request.headers[HTTPHeader("Mcp-Session-Id")]
                let response = await handler.handlePost(body: body, sessionID: sessionID)
                var headers: [HTTPHeader: String] = [:]
                for (key, value) in response.headers {
                    headers[HTTPHeader(key)] = value
                }
                return HTTPResponse(
                    statusCode: HTTPStatusCode(response.status, phrase: ""),
                    headers: headers,
                    body: response.body
                )
            }

            do {
                appLog("Local MCP server listening on 127.0.0.1:\(config.port)")
                try await server.run()
            } catch {
                appLog("Local MCP server stopped: \(error.localizedDescription)")
            }
        }
    }

    func stop() async {
        await server?.stop()
        serverTask?.cancel()
        serverTask = nil
        server = nil
    }
}
