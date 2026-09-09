#!/usr/bin/env bash

set -e

echo "=========================================="
echo " CONFIGURATION PUSH FIREBASE PARTENAIREFOYER"
echo "=========================================="

APP_GRADLE="android/app/build.gradle"
MAIN_DIR="android/app/src/main/java"

if [ ! -f "$APP_GRADLE" ]; then
  echo "ERREUR : $APP_GRADLE introuvable"
  exit 1
fi

if [ ! -d "$MAIN_DIR" ]; then
  echo "ERREUR : $MAIN_DIR introuvable"
  exit 1
fi


# ============================================================
# 1. FIREBASE MESSAGING
# ============================================================

echo ""
echo "Ajout de Firebase Messaging..."

python3 <<'PY'

from pathlib import Path

path = Path("android/app/build.gradle")

text = path.read_text()

dependency = "implementation 'com.google.firebase:firebase-messaging:24.1.2'"

if dependency not in text:

    marker = "dependencies {"

    if marker not in text:
        raise SystemExit(
            "Bloc dependencies introuvable dans android/app/build.gradle"
        )

    text = text.replace(
        marker,
        marker + "\n    " + dependency,
        1
    )

    path.write_text(text)

print("Firebase Messaging configuré.")

PY


# ============================================================
# 2. TROUVER MAINACTIVITY
# ============================================================

MAIN_ACTIVITY=$(find \
  "$MAIN_DIR" \
  -type f \
  -name "MainActivity.java" \
  | head -n 1)

if [ -z "$MAIN_ACTIVITY" ]; then
  echo "ERREUR : MainActivity.java introuvable"
  exit 1
fi

echo ""
echo "MainActivity : $MAIN_ACTIVITY"


# ============================================================
# 3. MODIFIER MAINACTIVITY
# ============================================================

python3 - "$MAIN_ACTIVITY" <<'PY'

from pathlib import Path
import sys

path = Path(sys.argv[1])

text = path.read_text()


# ------------------------------------------------------------
# IMPORTS
# ------------------------------------------------------------

imports = """
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import com.google.firebase.messaging.FirebaseMessaging;

import org.json.JSONObject;
"""


package_end = text.find(";")

if package_end == -1:
    raise SystemExit("Package Java introuvable")


for import_line in [
    "import android.os.Handler;",
    "import android.os.Looper;",
    "import android.util.Log;",
    "import com.google.firebase.messaging.FirebaseMessaging;",
    "import org.json.JSONObject;",
]:
    if import_line not in text:

        package_end = text.find(";")

        text = (
            text[:package_end + 1]
            + "\n"
            + import_line
            + text[package_end + 1:]
        )


# Bundle peut déjà exister à cause de la configuration WebView.

if "import android.os.Bundle;" not in text:

    package_end = text.find(";")

    text = (
        text[:package_end + 1]
        + "\nimport android.os.Bundle;"
        + text[package_end + 1:]
    )


# ------------------------------------------------------------
# MÉTHODES FCM
# ------------------------------------------------------------

marker = "PF_NATIVE_FCM_BRIDGE"

if marker not in text:

    class_end = text.rfind("}")

    if class_end == -1:
        raise SystemExit(
            "Fin de classe MainActivity introuvable"
        )

    block = r'''

    // ========================================================
    // PF_NATIVE_FCM_BRIDGE
    // Firebase Cloud Messaging -> WebView PartenaireFoyer
    // ========================================================

    private void initPartenaireFoyerPush() {

        FirebaseMessaging
            .getInstance()
            .getToken()
            .addOnCompleteListener(task -> {

                if (!task.isSuccessful()) {

                    Log.e(
                        "PartenaireFoyer",
                        "Impossible de récupérer le token FCM",
                        task.getException()
                    );

                    return;
                }

                String token = task.getResult();

                if (
                    token == null ||
                    token.trim().isEmpty()
                ) {
                    return;
                }

                Log.d(
                    "PartenaireFoyer",
                    "Token FCM récupéré"
                );

                sendFcmTokenToWebsite(
                    token
                );
            });
    }


    private void sendFcmTokenToWebsite(
        String token
    ) {

        try {

            JSONObject payload =
                new JSONObject();

            payload.put(
                "token",
                token
            );

            payload.put(
                "platform",
                "android"
            );

            String json =
                payload.toString();

            String js =
                "(function(){" +
                "try{" +

                "window.__PF_FCM_TOKEN__=" +
                JSONObject.quote(token) +
                ";" +

                "localStorage.setItem(" +
                "'pf_fcm_token'," +
                JSONObject.quote(token) +
                ");" +

                "window.dispatchEvent(" +
                "new CustomEvent(" +
                "'pf-native-fcm-token'," +
                "{detail:" +
                json +
                "}" +
                ")" +
                ");" +

                "}catch(e){" +
                "console.error(" +
                "'PF FCM bridge error'," +
                "e" +
                ");" +
                "}" +
                "})();";


            new Handler(
                Looper.getMainLooper()
            ).postDelayed(
                () -> {

                    if (
                        getBridge() == null ||
                        getBridge().getWebView() == null
                    ) {
                        return;
                    }

                    getBridge()
                        .getWebView()
                        .evaluateJavascript(
                            js,
                            null
                        );

                },
                4000
            );

        } catch (Exception error) {

            Log.e(
                "PartenaireFoyer",
                "Erreur bridge FCM",
                error
            );
        }
    }

'''

    text = (
        text[:class_end]
        + block
        + text[class_end:]
    )


# ------------------------------------------------------------
# APPELER FCM DEPUIS ONCREATE
# ------------------------------------------------------------

if "initPartenaireFoyerPush();" not in text:

    target = "super.onCreate(savedInstanceState);"

    if target in text:

        text = text.replace(
            target,
            target
            + """

        initPartenaireFoyerPush();
""",
            1
        )

    else:

        class_start = text.find("{")

        on_create = """

    @Override
    public void onCreate(
        Bundle savedInstanceState
    ) {

        super.onCreate(
            savedInstanceState
        );

        initPartenaireFoyerPush();
    }

"""

        text = (
            text[:class_start + 1]
            + on_create
            + text[class_start + 1:]
        )


path.write_text(text)

print(
    "MainActivity FCM configurée :",
    path
)

PY


# ============================================================
# 4. PERMISSION ANDROID 13+
# ============================================================

MANIFEST="android/app/src/main/AndroidManifest.xml"

python3 <<'PY'

from pathlib import Path

manifest = Path(
    "android/app/src/main/AndroidManifest.xml"
)

text = manifest.read_text()

permission = (
    '<uses-permission '
    'android:name="android.permission.POST_NOTIFICATIONS" />'
)

if (
    "android.permission.POST_NOTIFICATIONS"
    not in text
):

    text = text.replace(
        "<application",
        permission
        + "\n\n    <application",
        1
    )

manifest.write_text(
    text
)

print(
    "Permission POST_NOTIFICATIONS OK"
)

PY


echo ""
echo "=========================================="
echo " PUSH FIREBASE CONFIGURÉ"
echo "=========================================="
