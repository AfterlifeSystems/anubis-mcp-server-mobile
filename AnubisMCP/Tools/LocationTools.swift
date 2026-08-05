import CoreLocation
import Foundation

enum LocationTools {
    static func all() -> [MCPTool] {
        [getLocation]
    }

    static let getLocation = MCPTool(
        name: "get_location",
        description: "Get the phone's current location (latitude, longitude, accuracy). Requires location permission.",
        inputSchema: Schema.object([:])
    ) { _ in
        let location = try await LocationFetcher.shared.currentLocation()
        return [.text(JSON.encodeString([
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "horizontal_accuracy_m": location.horizontalAccuracy,
            "timestamp": location.timestamp.isoString,
        ]))]
    }
}

/// One-shot CLLocationManager wrapper bridging the delegate to async/await.
@MainActor
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    static let shared = LocationFetcher()

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func currentLocation() async throws -> CLLocation {
        if continuation != nil {
            throw ToolError("A location request is already in progress")
        }
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .denied || status == .restricted {
            throw ToolError("Location permission denied")
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.manager.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
            self.continuation?.resume(returning: location)
            self.continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.continuation?.resume(throwing: ToolError("Location failed: \(error.localizedDescription)"))
            self.continuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if self.continuation != nil {
                    self.manager.requestLocation()
                }
            } else if status == .denied || status == .restricted {
                self.continuation?.resume(throwing: ToolError("Location permission denied"))
                self.continuation = nil
            }
        }
    }
}
