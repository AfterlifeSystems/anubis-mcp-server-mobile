import UIKit

/// UIApplicationDelegate for the push-to-wake path. SwiftUI reaches this via
/// `UIApplicationDelegateAdaptor`. Silent (`content-available`) pushes need no
/// user authorization, so registration is non-interactive — fitting an app the
/// LLM drives rather than the user.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        appLog("APNs token registered (\(hex.prefix(12))…)")
        Task { @MainActor in ServerController.shared.updatePushToken(hex) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Expected on the simulator without a push-enabled provisioning profile;
        // the relay still works while foregrounded. Wake-handling is exercised
        // via `xcrun simctl push`, which does not need a real token.
        appLog("APNs registration unavailable: \(error.localizedDescription)")
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        // anubismcp://wake — Shortcut / App-Intent hook to force a relay wake;
        // also exercises the push wake code path in the simulator, where silent
        // pushes are not delivered to the background handler.
        appLog("Opened URL: \(url.absoluteString)")
        if url.host == "wake" || url.absoluteString.contains("wake") {
            Task { @MainActor in ServerController.shared.wake(reason: "url-trigger") }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            ServerController.shared.wake(reason: "apns-silent-push") { hadActivity in
                completionHandler(hadActivity ? .newData : .noData)
            }
        }
    }
}
