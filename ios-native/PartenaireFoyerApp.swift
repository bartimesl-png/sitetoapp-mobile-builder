import SwiftUI

@main
struct PartenaireFoyerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(Color(red: 0.02, green: 0.38, blue: 0.34))
        }
    }
}
