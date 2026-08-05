import Foundation
import os

/// In-memory ring buffer of log lines surfaced in StatusView, mirrored to os.Logger.
@MainActor
final class AppLog: ObservableObject {
    static let shared = AppLog()

    struct Line: Identifiable {
        let id = UUID()
        let date: Date
        let text: String
    }

    @Published private(set) var lines: [Line] = []
    private let logger = Logger(subsystem: "site.neuralnexus.anubis-mcp", category: "app")
    private let maxLines = 400

    nonisolated func log(_ text: String) {
        Task { @MainActor in
            self.logger.info("\(text, privacy: .public)")
            self.lines.append(Line(date: Date(), text: text))
            if self.lines.count > self.maxLines {
                self.lines.removeFirst(self.lines.count - self.maxLines)
            }
        }
    }
}

func appLog(_ text: String) {
    AppLog.shared.log(text)
}
