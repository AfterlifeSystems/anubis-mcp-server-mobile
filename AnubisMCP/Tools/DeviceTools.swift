import Foundation
import UIKit
import UserNotifications

enum DeviceTools {
    static func all() -> [MCPTool] {
        [deviceInfo, batteryStatus, clipboardGet, clipboardSet, sendNotification]
    }

    static let deviceInfo = MCPTool(
        name: "device_info",
        description: "Get information about this iPhone: name, model, iOS version, locale, timezone, battery.",
        inputSchema: Schema.object([:])
    ) { _ in
        let info: [String: Any] = await MainActor.run {
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            return [
                "name": device.name,
                "model": device.model,
                "system_name": device.systemName,
                "system_version": device.systemVersion,
                "identifier_for_vendor": device.identifierForVendor?.uuidString ?? "unknown",
                "locale": Locale.current.identifier,
                "timezone": TimeZone.current.identifier,
                "battery_level": device.batteryLevel,
                "battery_state": batteryStateName(device.batteryState),
                "local_time": Date().isoString,
            ]
        }
        return [.text(JSON.encodeString(info))]
    }

    static let batteryStatus = MCPTool(
        name: "battery_status",
        description: "Get the current battery level (0.0-1.0, -1 if unknown) and charging state.",
        inputSchema: Schema.object([:])
    ) { _ in
        let info: [String: Any] = await MainActor.run {
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            return [
                "battery_level": device.batteryLevel,
                "battery_state": batteryStateName(device.batteryState),
            ]
        }
        return [.text(JSON.encodeString(info))]
    }

    static let clipboardGet = MCPTool(
        name: "clipboard_get",
        description: "Read the current text content of the clipboard.",
        inputSchema: Schema.object([:])
    ) { _ in
        let text = await MainActor.run { UIPasteboard.general.string ?? "" }
        return [.text(JSON.encodeString(["text": text]))]
    }

    static let clipboardSet = MCPTool(
        name: "clipboard_set",
        description: "Replace the clipboard content with the given text.",
        inputSchema: Schema.object(["text": Schema.string("Text to place on the clipboard")], required: ["text"])
    ) { args in
        guard let text = args["text"] as? String else { throw ToolError("Missing 'text' argument") }
        await MainActor.run { UIPasteboard.general.string = text }
        return [.text(JSON.encodeString(["ok": true]))]
    }

    static let sendNotification = MCPTool(
        name: "send_notification",
        description: "Show a local notification on the phone with a title and message body.",
        inputSchema: Schema.object(
            [
                "title": Schema.string("Notification title"),
                "body": Schema.string("Notification body text"),
            ],
            required: ["title", "body"]
        )
    ) { args in
        guard let title = args["title"] as? String, let body = args["body"] as? String else {
            throw ToolError("Missing 'title' or 'body' argument")
        }
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else { throw ToolError("Notification permission denied") }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )
        try await center.add(request)
        return [.text(JSON.encodeString(["ok": true]))]
    }

    private static func batteryStateName(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging: return "charging"
        case .full: return "full"
        case .unplugged: return "unplugged"
        default: return "unknown"
        }
    }
}
