import Foundation

/// JSONSerialization conveniences for the dynamic JSON-RPC / relay frames.
enum JSON {
    static func encode(_ object: Any) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    static func encodeString(_ object: Any) -> String {
        String(data: encode(object), encoding: .utf8) ?? "{}"
    }

    static func decodeObject(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func decodeObject(_ string: String) -> [String: Any]? {
        decodeObject(Data(string.utf8))
    }
}

extension String {
    /// ISO-8601 date parsing that accepts values with or without fractional seconds.
    var parsedISODate: Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: self) { return date }
        let plain = ISO8601DateFormatter()
        return plain.date(from: self)
    }
}

extension Date {
    var isoString: String {
        ISO8601DateFormatter().string(from: self)
    }
}
