import SwiftUI
import WebKit

/// Minimal operator console: the app is driven by the avatar, not the user.
/// Shows connection state, lets the user paste their API key once, tails the
/// log, and hosts the automation browser so tool activity is visible.
struct StatusView: View {
    @EnvironmentObject var controller: ServerController
    @ObservedObject var log = AppLog.shared
    @State private var apiKeyInput = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    row("Local MCP server", controller.serverRunning
                        ? "127.0.0.1:\(controller.config.port)" : "stopped",
                        good: controller.serverRunning)
                    row("Relay", controller.relayState.rawValue,
                        good: controller.relayState == .registered || controller.relayState == .connected)
                    row("Push-to-wake", controller.pushToken == nil ? "unavailable (sim)" : "armed",
                        good: controller.pushToken != nil)
                    row("API", controller.config.apiBaseURL, good: true)
                    row("Device ID", controller.config.deviceID, good: true)
                    row("Server name", controller.config.serverName, good: true)
                }

                Section("API key") {
                    if controller.hasAPIKey {
                        Label("API key configured", systemImage: "key.fill")
                            .foregroundStyle(.green)
                    }
                    SecureField("sk-...", text: $apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save API key") {
                        controller.saveAPIKey(apiKeyInput)
                        apiKeyInput = ""
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section("Automation browser") {
                    BrowserHostView(webView: controller.browser.webView)
                        .frame(height: 300)
                        .listRowInsets(EdgeInsets())
                }

                Section("Log") {
                    ForEach(log.lines.suffix(60).reversed()) { line in
                        Text("\(line.date.formatted(date: .omitted, time: .standard))  \(line.text)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Anubis MCP")
        }
    }

    private func row(_ label: String, _ value: String, good: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(good ? Color.green : Color.orange)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

struct BrowserHostView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
