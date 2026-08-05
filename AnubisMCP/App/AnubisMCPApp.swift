import SwiftUI

@main
struct AnubisMCPApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = ServerController.shared

    var body: some Scene {
        WindowGroup {
            StatusView()
                .environmentObject(controller)
                .onAppear {
                    controller.start()
                }
        }
    }
}
