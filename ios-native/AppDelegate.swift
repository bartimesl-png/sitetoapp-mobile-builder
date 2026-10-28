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
        // AsyncImage uses URLSession.shared; this disk cache avoids downloading
        // the same listing photos again when users browse between screens.
        URLCache.shared = URLCache(
            memoryCapacity: 48 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "partenairefoyer-image-cache"
        )

        FirebaseApp.configure()

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        Messaging.messaging().delegate = self
        return true
    }

    static func requestPushAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await withCheckedContinuation { continuation in
            center.getNotificationSettings { continuation.resume(returning: $0) }
        }
        guard settings.authorizationStatus != .denied else { return false }

        if settings.authorizationStatus == .notDetermined {
            let granted = await withCheckedContinuation { continuation in
                center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
                    if let error {
                        NSLog("Notifications iOS: autorisation impossible: %@", error.localizedDescription)
                    }
                    continuation.resume(returning: granted && error == nil)
                }
            }
            guard granted else { return false }
        }

        UIApplication.shared.registerForRemoteNotifications()
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

    static let pendingPushTapKey = "partenairefoyer.pendingPushTap.v1"

    static func stringFields(from userInfo: [AnyHashable: Any]) -> [String: String] {
        let allowedKeys: Set<String> = [
            "role", "accountType", "recipientRole", "eventType", "entityId",
            "conversationId", "matchingId", "opportunityId",
        ]
        var fields: [String: String] = [:]
        for (rawKey, value) in userInfo {
            guard let key = rawKey as? String else { continue }
            if allowedKeys.contains(key), let string = value as? String {
                fields[key] = string
            } else if key == "data", let nested = value as? [AnyHashable: Any] {
                for (nestedKey, nestedValue) in nested {
                    if let nestedKey = nestedKey as? String,
                       allowedKeys.contains(nestedKey), let nestedValue = nestedValue as? String {
                        fields[nestedKey] = nestedValue
                    }
                }
            }
        }
        return fields
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let fields = AppDelegate.stringFields(from: response.notification.request.content.userInfo)
        UserDefaults.standard.set(fields, forKey: AppDelegate.pendingPushTapKey)
        NotificationCenter.default.post(name: .partenaireFoyerPushNotificationTapped, object: fields)
        completionHandler()
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
    static let partenaireFoyerPushNotificationTapped =
        Notification.Name("partenairefoyer.pushNotificationTapped")
}
