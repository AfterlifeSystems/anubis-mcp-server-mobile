import Foundation

/// MCP tool wrappers around BrowserAutomator — full browser use inside the app.
enum BrowserTools {
    static func all(browser: BrowserAutomator) -> [MCPTool] {
        [
            MCPTool(
                name: "browser_navigate",
                description: "Load an http(s) URL in the in-app browser. Returns the final URL and title. Follow with browser_snapshot to see the page.",
                inputSchema: Schema.object(["url": Schema.string("The http(s) URL to load")], required: ["url"])
            ) { args in
                guard let url = args["url"] as? String else { throw ToolError("Missing 'url' argument") }
                let result = try await browser.navigate(to: url)
                return [.text(result)]
            },
            MCPTool(
                name: "browser_snapshot",
                description: "Get a compact outline of the current page: visible text plus an indexed list of interactive elements (links, buttons, inputs). Use the element index with browser_click / browser_fill.",
                inputSchema: Schema.object(["max_text_length": Schema.integer("Max characters of page text to include (default 3000)")])
            ) { args in
                let maxLength = (args["max_text_length"] as? Int) ?? 3000
                let result = try await browser.snapshot(maxTextLength: max(200, maxLength))
                return [.text(result)]
            },
            MCPTool(
                name: "browser_click",
                description: "Click an element on the current page, by element index from browser_snapshot or by CSS selector.",
                inputSchema: Schema.object(
                    [
                        "index": Schema.integer("Element index from the latest browser_snapshot"),
                        "selector": Schema.string("CSS selector, used when no index is given"),
                    ]
                )
            ) { args in
                let result = try await browser.click(
                    index: args["index"] as? Int,
                    selector: args["selector"] as? String
                )
                return [.text(result)]
            },
            MCPTool(
                name: "browser_fill",
                description: "Type text into an input or textarea, by element index from browser_snapshot or by CSS selector.",
                inputSchema: Schema.object(
                    [
                        "index": Schema.integer("Element index from the latest browser_snapshot"),
                        "selector": Schema.string("CSS selector, used when no index is given"),
                        "text": Schema.string("The text to enter"),
                    ],
                    required: ["text"]
                )
            ) { args in
                guard let text = args["text"] as? String else { throw ToolError("Missing 'text' argument") }
                let result = try await browser.fill(
                    index: args["index"] as? Int,
                    selector: args["selector"] as? String,
                    text: text
                )
                return [.text(result)]
            },
            MCPTool(
                name: "browser_evaluate_js",
                description: "Run a JavaScript expression on the current page and return its result as a string.",
                inputSchema: Schema.object(["script": Schema.string("JavaScript to evaluate")], required: ["script"])
            ) { args in
                guard let script = args["script"] as? String else { throw ToolError("Missing 'script' argument") }
                let result = try await browser.evaluate(script)
                return [.text(String(describing: result ?? "null"))]
            },
            MCPTool(
                name: "browser_screenshot",
                description: "Take a JPEG screenshot of the current page in the in-app browser.",
                inputSchema: Schema.object([:])
            ) { _ in
                let base64 = try await browser.screenshot()
                return [.image(base64: base64, mimeType: "image/jpeg")]
            },
            MCPTool(
                name: "browser_back",
                description: "Go back one page in the in-app browser history.",
                inputSchema: Schema.object([:])
            ) { _ in
                let result = try await browser.goBack()
                return [.text(result)]
            },
        ]
    }
}
