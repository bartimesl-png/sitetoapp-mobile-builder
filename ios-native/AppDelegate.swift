import FirebaseCore
import FirebaseMessaging
import UIKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseApp.configure()

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Messaging.messaging().delegate = self

        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                NSLog("Notifications iOS: autorisation impossible: %@", error.localizedDescription)
            }
            guard granted else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        NSLog("Notifications iOS: enregistrement APNs impossible: %@", error.localizedDescription)
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken, !fcmToken.isEmpty else { return }

        UserDefaults.standard.set(fcmToken, forKey: "partenairefoyer.fcmRegistrationToken")
        NotificationCenter.default.post(
            name: .partenaireFoyerFCMTokenDidChange,
            object: fcmToken
        )
        NSLog("Firebase Messaging: jeton FCM enregistré.")
    }
}

extension Notification.Name {
    static let partenaireFoyerFCMTokenDidChange =
        Notification.Name("partenairefoyer.fcmRegistrationTokenDidChange")
}
