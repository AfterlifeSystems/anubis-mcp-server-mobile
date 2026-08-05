import Foundation

/// Calling, texting, and email composition. iOS always shows the user a
/// confirmation (call prompt / prefilled compose screen) — the avatar
/// initiates, the user approves on screen.
enum CommsTools {
    static func all() -> [MCPTool] {
        [placeCall, composeSMS, composeEmail]
    }

    static let placeCall = MCPTool(
        name: "place_call",
        description: "Start a phone call to the given number (e.g. to call a restaurant to place an order). iOS shows the user a call confirmation.",
        inputSchema: Schema.object(["number": Schema.string("Phone number to dial, digits with optional +country code")], required: ["number"])
    ) { args in
        guard let number = args["number"] as? String else { throw ToolError("Missing 'number' argument") }
        let cleaned = number.filter { "+0123456789".contains($0) }
        guard !cleaned.isEmpty else { throw ToolError("No dialable digits in '\(number)'") }
        return try await AppLaunchTools.open(urlString: "tel://\(cleaned)", label: "Phone call to \(cleaned)")
    }

    static let composeSMS = MCPTool(
        name: "compose_sms",
        description: "Open Messages with a prefilled text to the given recipient; the user taps send.",
        inputSchema: Schema.object(
            [
                "recipient": Schema.string("Phone number or contact handle"),
                "body": Schema.string("Message text to prefill"),
            ],
            required: ["recipient"]
        )
    ) { args in
        guard let recipient = args["recipient"] as? String else { throw ToolError("Missing 'recipient' argument") }
        var urlString = "sms:\(recipient.filter { "+0123456789".contains($0) })"
        if let body = args["body"] as? String,
           let encoded = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "&body=\(encoded)"
        }
        return try await AppLaunchTools.open(urlString: urlString, label: "Message to \(recipient)")
    }

    static let composeEmail = MCPTool(
        name: "compose_email",
        description: "Open Mail with a prefilled email; the user taps send.",
        inputSchema: Schema.object(
            [
                "to": Schema.string("Recipient email address"),
                "subject": Schema.string("Email subject"),
                "body": Schema.string("Email body text"),
            ],
            required: ["to"]
        )
    ) { args in
        guard let to = args["to"] as? String else { throw ToolError("Missing 'to' argument") }
        var components = URLComponents(string: "mailto:\(to)")!
        var items: [URLQueryItem] = []
        if let subject = args["subject"] as? String { items.append(URLQueryItem(name: "subject", value: subject)) }
        if let body = args["body"] as? String { items.append(URLQueryItem(name: "body", value: body)) }
        if !items.isEmpty { components.queryItems = items }
        guard let url = components.url else { throw ToolError("Could not build mailto URL") }
        return try await AppLaunchTools.open(urlString: url.absoluteString, label: "Email to \(to)")
    }
}
