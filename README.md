# SiteToApp Mobile Builder

Builds the SiteToApp Android test app and the native PartenaireFoyer iOS app.

## iOS Firebase Cloud Messaging

The native iOS target uses Firebase Messaging through Swift Package Manager. Before the iOS build, Codemagic must make the iOS Firebase configuration available as `GOOGLE_SERVICE_INFO_PLIST_BASE64` or the existing alias `IOS_FIREBASE_PLIST_BASE64` (Base64 contents), or as `GOOGLE_SERVICE_INFO_PLIST` (raw plist contents or a path to a plist file). The plist must belong to bundle ID `com.partenairefoyer.app`; Android's `google-services.json` cannot be used for iOS.

In Firebase Console, register an iOS app in project `partenairefoyer-29069` with bundle ID `com.partenairefoyer.app` and download its `GoogleService-Info.plist`. Store its contents in a protected Codemagic environment variable. Do not commit the plist or put its contents in YAML.

In Firebase Console > Project settings > Cloud Messaging, upload the Apple APNs authentication key (.p8) for the same Apple developer team. The Apple App ID and App Store provisioning profile must have Push Notifications enabled.

The app requests notification permission on first launch, registers with APNs, forwards the APNs token to Firebase Messaging, and stores refreshed FCM registration tokens on-device. A server must still address the FCM token (or a topic) to send application-specific notifications.
