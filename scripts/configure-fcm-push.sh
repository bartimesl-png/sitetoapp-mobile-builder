#!/usr/bin/env bash
set -euo pipefail

echo "===== SITETOAPP - CONFIGURATION FCM NATIVE ====="

APP_GRADLE="android/app/build.gradle"
ROOT_GRADLE="android/build.gradle"
MANIFEST="android/app/src/main/AndroidManifest.xml"
JAVA_ROOT="android/app/src/main/java"

if [ ! -f "$APP_GRADLE" ]; then
  echo "ERREUR : $APP_GRADLE introuvable"
  exit 1
fi

if [ ! -f "$ROOT_GRADLE" ]; then
  echo "ERREUR : $ROOT_GRADLE introuvable"
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "ERREUR : $MANIFEST introuvable"
  exit 1
fi

if [ ! -f "android/app/google-services.json" ]; then
  echo "ERREUR : android/app/google-services.json introuvable"
  exit 1
fi

MAIN_ACTIVITY=$(find "$JAVA_ROOT" -type f -name MainActivity.java | head -n 1 || true)

if [ -z "$MAIN_ACTIVITY" ]; then
  echo "ERREUR : MainActivity.java introuvable"
  exit 1
fi

PACKAGE_NAME=$(sed -n 's/^package[[:space:]]\+\([^;]*\);/\1/p' "$MAIN_ACTIVITY" | head -n 1)

if [ -z "$PACKAGE_NAME" ]; then
  PACKAGE_NAME="${APP_PACKAGE_ID:-}"
fi

if [ -z "$PACKAGE_NAME" ]; then
  echo "ERREUR : package Android introuvable"
  exit 1
fi

PACKAGE_DIR=$(dirname "$MAIN_ACTIVITY")

echo "Package Android : $PACKAGE_NAME"
echo "MainActivity : $MAIN_ACTIVITY"

python3 <<'PY'
from pathlib import Path
import re

root = Path("android/build.gradle")
app = Path("android/app/build.gradle")

root_text = root.read_text()
root_text = re.sub(
    r"com\.google\.gms:google-services:[0-9.]+",
    "com.google.gms:google-services:4.5.0",
    root_text,
)
root.write_text(root_text)

app_text = app.read_text()

match = re.search(r"dependencies\s*\{", app_text)
if not match:
    raise SystemExit("Bloc dependencies introuvable dans android/app/build.gradle")

lines = []
if "com.google.firebase:firebase-bom" not in app_text:
    lines.append("    implementation platform('com.google.firebase:firebase-bom:34.18.0')")
if "com.google.firebase:firebase-messaging" not in app_text:
    lines.append("    implementation 'com.google.firebase:firebase-messaging'")

if lines:
    pos = match.end()
    app_text = app_text[:pos] + "\n" + "\n".join(lines) + "\n" + app_text[pos:]

plugin_line = "apply plugin: 'com.google.gms.google-services'"
if plugin_line not in app_text:
    app_text += "\n" + plugin_line + "\n"

app.write_text(app_text)
PY

cat > "$MAIN_ACTIVITY" <<JAVA
package $PACKAGE_NAME;

import android.Manifest;
import android.content.pm.PackageManager;
import android.os.Build;
import android.os.Bundle;
import android.webkit.WebView;

import com.getcapacitor.BridgeActivity;
import com.google.firebase.messaging.FirebaseMessaging;

import org.json.JSONObject;

public class MainActivity extends BridgeActivity {

    private static final int NOTIFICATION_PERMISSION_REQUEST_CODE = 9001;
    private WebView siteToAppWebView;

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        siteToAppWebView = getBridge().getWebView();

        requestNotificationPermissionIfNeeded();

        FirebaseMessaging.getInstance().setAutoInitEnabled(true);

        FirebaseMessaging.getInstance()
            .getToken()
            .addOnCompleteListener(task -> {
                if (!task.isSuccessful()) {
                    System.out.println(
                        "SiteToApp FCM : récupération du token impossible : "
                        + task.getException()
                    );
                    return;
                }

                String token = task.getResult();

                if (token == null || token.isEmpty()) {
                    System.out.println("SiteToApp FCM : token vide");
                    return;
                }

                saveFcmToken(token);
                scheduleTokenDelivery(token);
            });
    }

    @Override
    public void onResume()
        super.onResume();

        String token = getSharedPreferences(
            "sitetoapp_push",
            MODE_PRIVATE
        ).getString("fcm_token", null);

        if (token != null && !token.isEmpty()) {
            scheduleTokenDelivery(token);
            return;
        }

        FirebaseMessaging.getInstance()
            .getToken()
            .addOnCompleteListener(task -> {
                if (!task.isSuccessful()) {
                    return;
                }

                String freshToken = task.getResult();

                if (freshToken != null && !freshToken.isEmpty()) {
                    saveFcmToken(freshToken);
                    scheduleTokenDelivery(freshToken);
                }
            });
    }

    private void requestNotificationPermissionIfNeeded() {
        if (
            Build.VERSION.SDK_INT >= 33
            && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                new String[]{Manifest.permission.POST_NOTIFICATIONS},
                NOTIFICATION_PERMISSION_REQUEST_CODE
            );
        }
    }

    private void saveFcmToken(String token) {
        getSharedPreferences(
            "sitetoapp_push",
            MODE_PRIVATE
        )
            .edit()
            .putString("fcm_token", token)
            .apply();
    }

    private void scheduleTokenDelivery(String token) {
        if (siteToAppWebView == null) {
            siteToAppWebView = getBridge().getWebView();
        }

        final String finalToken = token;
        long[] delays = new long[]{500, 1500, 3000, 6000, 10000};

        for (long delay : delays) {
            siteToAppWebView.postDelayed(
                () -> sendTokenToWebView(finalToken),
                delay
            );
        }
    }

    private void sendTokenToWebView(String token) {
        if (siteToAppWebView == null || token == null || token.isEmpty()) {
            return;
        }

        final String quotedToken = JSONObject.quote(token);

        final String script =
            "(function(){" +
            "try{" +
            "var token=" + quotedToken + ";" +
            "window.__ANDROID_FCM_TOKEN__=token;" +
            "window.__FCM_TOKEN__=token;" +
            "try{localStorage.setItem('androidFcmToken',token);}catch(e){}" +
            "try{localStorage.setItem('fcmToken',token);}catch(e){}" +
            "try{localStorage.setItem('FCM_TOKEN',token);}catch(e){}" +
            "try{window.dispatchEvent(new CustomEvent('android-fcm-token',{detail:{token:token}}));}catch(e){}" +
            "try{window.dispatchEvent(new CustomEvent('fcm-token',{detail:{token:token}}));}catch(e){}" +
            "try{window.dispatchEvent(new CustomEvent('native-fcm-token',{detail:{token:token}}));}catch(e){}" +
            "try{window.postMessage({type:'FCM_TOKEN',token:token,source:'android-native'},'*');}catch(e){}" +
            "try{window.postMessage({type:'ANDROID_FCM_TOKEN',token:token,source:'android-native'},'*');}catch(e){}" +
            "console.log('SiteToApp FCM token transmis à la page');" +
            "}catch(e){console.error('SiteToApp FCM bridge',e);}" +
            "})();";

        siteToAppWebView.post(
            () -> siteToAppWebView.evaluateJavascript(script, null)
        );
    }
}
JAVA

cat > "$PACKAGE_DIR/SiteToAppFirebaseMessagingService.java" <<JAVA
package $PACKAGE_NAME;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Intent;
import android.os.Build;

import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;

public class SiteToAppFirebaseMessagingService extends FirebaseMessagingService {

    private static final String CHANNEL_ID = "sitetoapp_notifications";

    @Override
    public void onNewToken(String token) {
        super.onNewToken(token);

        if (token == null || token.isEmpty()) {
            return;
        }

        getSharedPreferences(
            "sitetoapp_push",
            MODE_PRIVATE
        )
            .edit()
            .putString("fcm_token", token)
            .apply();

        System.out.println("SiteToApp FCM : nouveau token enregistré");
    }

    @Override
    public void onMessageReceived(RemoteMessage remoteMessage) {
        super.onMessageReceived(remoteMessage);

        String title = "PartenaireFoyer";
        String body = "Vous avez une nouvelle notification.";

        if (remoteMessage.getNotification() != null) {
            if (remoteMessage.getNotification().getTitle() != null) {
                title = remoteMessage.getNotification().getTitle();
            }

            if (remoteMessage.getNotification().getBody() != null) {
                body = remoteMessage.getNotification().getBody();
            }
        } else {
            if (remoteMessage.getData().containsKey("title")) {
                title = remoteMessage.getData().get("title");
            }

            if (remoteMessage.getData().containsKey("body")) {
                body = remoteMessage.getData().get("body");
            }
        }

        showNotification(title, body);
    }

    private void showNotification(String title, String body) {
        NotificationManager manager =
            (NotificationManager) getSystemService(NOTIFICATION_SERVICE);

        if (manager == null) {
            return;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                CHANNEL_ID,
                "Notifications PartenaireFoyer",
                NotificationManager.IMPORTANCE_HIGH
            );

            channel.setDescription(
                "Messages et notifications PartenaireFoyer"
            );

            manager.createNotificationChannel(channel);
        }

        Intent intent = new Intent(this, MainActivity.class);
        intent.addFlags(
            Intent.FLAG_ACTIVITY_CLEAR_TOP
            | Intent.FLAG_ACTIVITY_SINGLE_TOP
        );

        PendingIntent pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT
                | PendingIntent.FLAG_IMMUTABLE
        );

        android.app.Notification.Builder builder;

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            builder = new android.app.Notification.Builder(
                this,
                CHANNEL_ID
            );
        } else {
            builder = new android.app.Notification.Builder(this);
        }

        builder
            .setSmallIcon(getApplicationInfo().icon)
            .setContentTitle(title)
            .setContentText(body)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent);

        manager.notify(
            (int) (System.currentTimeMillis() % Integer.MAX_VALUE),
            builder.build()
        );
    }
}
JAVA

python3 <<'PY'
from pathlib import Path

manifest = Path("android/app/src/main/AndroidManifest.xml")
text = manifest.read_text()

permission = '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />'
if permission not in text:
    text = text.replace(
        "<application",
        permission + "\n\n    <application",
        1,
    )

service_block = '''
        <service
            android:name=".SiteToAppFirebaseMessagingService"
            android:exported="false">
            <intent-filter>
                <action android:name="com.google.firebase.MESSAGING_EVENT" />
            </intent-filter>
        </service>

        <meta-data
            android:name="com.google.firebase.messaging.default_notification_icon"
            android:resource="@mipmap/ic_launcher" />
'''

if "SiteToAppFirebaseMessagingService" not in text:
    text = text.replace(
        "</application>",
        service_block + "\n    </application>",
        1,
    )

manifest.write_text(text)
PY

echo ""
echo "===== VERIFICATION FINALE FCM ====="

grep -n "firebase-messaging" "$APP_GRADLE"
grep -R -n "FirebaseMessaging" "$JAVA_ROOT"
grep -n "POST_NOTIFICATIONS" "$MANIFEST"
grep -n "SiteToAppFirebaseMessagingService\|MESSAGING_EVENT" "$MANIFEST"

echo ""
echo "FCM natif + pont WebView configurés avec succès."
