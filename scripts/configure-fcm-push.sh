#!/usr/bin/env bash

set -e

echo "=========================================="
echo " CONFIGURATION PUSH FIREBASE PARTENAIREFOYER"
echo "=========================================="

APP_GRADLE="android/app/build.gradle"
MAIN_DIR="android/app/src/main/java"
MANIFEST="android/app/src/main/AndroidManifest.xml"

if [ ! -f "$APP_GRADLE" ]; then
  echo "ERREUR : $APP_GRADLE introuvable"
  exit 1
fi

if [ ! -d "$MAIN_DIR" ]; then
  echo "ERREUR : $MAIN_DIR introuvable"
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "ERREUR : $MANIFEST introuvable"
  exit 1
fi


# ============================================================
# 1. FIREBASE MESSAGING
# ============================================================

echo ""
echo "Ajout de Firebase Messaging..."

python3 <<'PY'

from pathlib import Path

path = Path(
    "android/app/build.gradle"
)

text = path.read_text()

dependency = (
    "implementation "
    "'com.google.firebase:"
    "firebase-messaging:24.1.2'"
)

if dependency not in text:

    marker = "dependencies {"

    if marker not in text:
        raise SystemExit(
            "Bloc dependencies introuvable "
            "dans android/app/build.gradle"
        )

    text = text.replace(
        marker,
        marker
        + "\n    "
        + dependency,
        1
    )

    path.write_text(text)

print(
    "Firebase Messaging configuré."
)

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
import re
import sys

path = Path(
    sys.argv[1]
)

text = path.read_text()


# ------------------------------------------------------------
# IMPORTS
# ------------------------------------------------------------

required_imports = [
    "import android.os.Bundle;",
    "import android.os.Handler;",
    "import android.os.Looper;",
    "import android.util.Log;",
    "import android.webkit.WebView;",
    (
        "import com.google.firebase.messaging."
        "FirebaseMessaging;"
    ),
]


package_match = re.search(
    r"package\s+[^;]+;",
    text
)

if not package_match:
    raise SystemExit(
        "Déclaration package Java introuvable"
    )


insert_position = (
    package_match.end()
)


for import_line in required_imports:

    if import_line in text:
        continue

    text = (
        text[:insert_position]
        + "\n"
        + import_line
        + text[insert_position:]
    )

    insert_position += (
        len(import_line)
        + 1
    )


# ------------------------------------------------------------
# SUPPRIMER UNE ANCIENNE VERSION DU BRIDGE
# ------------------------------------------------------------

old_start = (
    "// ========================================================\n"
    "    // PF_NATIVE_FCM_BRIDGE"
)

old_position = text.find(
    old_start
)

if old_position != -1:

    class_end = text.rfind(
        "}"
    )

    if class_end == -1:
        raise SystemExit(
            "Fin de classe MainActivity introuvable"
        )

    text = (
        text[:old_position]
        + text[class_end:]
    )


# ------------------------------------------------------------
# SUPPRIMER LES ANCIENS APPELS
# ------------------------------------------------------------

text = text.replace(
    "\n        initPartenaireFoyerPush();",
    ""
)

text = text.replace(
    "\n        schedulePartenaireFoyerPush();",
    ""
)


# ------------------------------------------------------------
# AJOUT DU NOUVEAU BRIDGE
# ------------------------------------------------------------

class_end = text.rfind(
    "}"
)

if class_end == -1:
    raise SystemExit(
        "Fin de classe MainActivity introuvable"
    )


bridge = r'''

    // ========================================================
    // PF_NATIVE_FCM_BRIDGE
    // Firebase Cloud Messaging -> WebView PartenaireFoyer
    // ========================================================

    private String pfFcmToken = null;

    private final Handler pfPushHandler =
        new Handler(
            Looper.getMainLooper()
        );


    private void initPartenaireFoyerPush() {

        Log.d(
            "PartenaireFoyer",
            "Initialisation Firebase FCM"
        );

        FirebaseMessaging
            .getInstance()
            .getToken()
            .addOnCompleteListener(
                task -> {

                    if (
                        !task.isSuccessful()
                    ) {

                        Log.e(
                            "PartenaireFoyer",
                            "Impossible de récupérer le token FCM",
                            task.getException()
                        );

                        return;
                    }


                    String token =
                        task.getResult();


                    if (
                        token == null ||
                        token.trim().isEmpty()
                    ) {

                        Log.e(
                            "PartenaireFoyer",
                            "Firebase a retourné un token FCM vide"
                        );

                        return;
                    }


                    pfFcmToken =
                        token.trim();


                    Log.d(
                        "PartenaireFoyer",
                        "Token FCM récupéré, longueur=" +
                        pfFcmToken.length()
                    );


                    schedulePartenaireFoyerPush();
                }
            );
    }


    private void schedulePartenaireFoyerPush() {

        if (
            pfFcmToken == null ||
            pfFcmToken.trim().isEmpty()
        ) {
            return;
        }


        /*
         * Plusieurs tentatives.
         *
         * Avec server.url, la WebView peut mettre
         * plusieurs secondes avant d'être réellement
         * arrivée sur partenairefoyer.com.
         */
        long[] delays = {
            1000,
            3000,
            6000,
            10000,
            15000,
            25000
        };


        for (
            long delay :
            delays
        ) {

            pfPushHandler.postDelayed(
                () -> sendFcmTokenToWebsite(
                    pfFcmToken
                ),
                delay
            );
        }
    }


    private void sendFcmTokenToWebsite(
        String token
    ) {

        if (
            token == null ||
            token.trim().isEmpty()
        ) {
            return;
        }


        if (
            getBridge() == null ||
            getBridge().getWebView() == null
        ) {

            Log.d(
                "PartenaireFoyer",
                "WebView pas encore disponible pour FCM"
            );

            return;
        }


        final WebView webView =
            getBridge()
                .getWebView();


        final String safeToken =
            org.json.JSONObject.quote(
                token
            );


        final String js =
            "(function(){" +

            "try{" +

            "var host='';" +

            "try{" +
                "host=(" +
                    "window.location.hostname||''" +
                ").toLowerCase();" +
            "}catch(e){}" +

            "if(" +
                "host!=='www.partenairefoyer.com'" +
                "&&" +
                "host!=='partenairefoyer.com'" +
            "){" +
                "return 'PF_WAITING_FOR_SITE:'+host;" +
            "}" +

            "window.__PF_FCM_TOKEN__=" +
                safeToken +
            ";" +

            /*
             * localStorage ne doit JAMAIS empêcher
             * l'envoi de l'événement.
             */
            "try{" +
                "window.localStorage.setItem(" +
                    "'pf_fcm_token'," +
                    safeToken +
                ");" +
            "}catch(storageError){" +
                "console.warn(" +
                    "'PF FCM localStorage indisponible'," +
                    "storageError" +
                ");" +
            "}" +

            "try{" +

                "window.dispatchEvent(" +
                    "new CustomEvent(" +
                        "'pf-native-fcm-token'," +
                        "{" +
                            "detail:{" +
                                "token:" +
                                    safeToken +
                                "," +
                                "platform:'android'" +
                            "}" +
                        "}" +
                    ")" +
                ");" +

            "}catch(eventError){" +

                /*
                 * Fallback pour WebView plus ancienne.
                 */
                "var pfEvent=" +
                    "document.createEvent(" +
                        "'CustomEvent'" +
                    ");" +

                "pfEvent.initCustomEvent(" +
                    "'pf-native-fcm-token'," +
                    "false," +
                    "false," +
                    "{" +
                        "token:" +
                            safeToken +
                        "," +
                        "platform:'android'" +
                    "}" +
                ");" +

                "window.dispatchEvent(" +
                    "pfEvent" +
                ");" +
            "}" +

            "console.log(" +
                "'[PF_NATIVE] Token FCM transmis au site'" +
            ");" +

            "return 'PF_FCM_SENT';" +

            "}catch(e){" +

                "console.error(" +
                    "'PF FCM bridge error'," +
                    "e" +
                ");" +

                "return 'PF_FCM_ERROR:'+" +
                    "String(e);" +

            "}" +

            "})();";


        pfPushHandler.post(
            () -> {

                try {

                    webView.evaluateJavascript(
                        js,
                        result -> {

                            Log.d(
                                "PartenaireFoyer",
                                "Résultat bridge FCM : " +
                                result
                            );
                        }
                    );

                } catch (
                    Exception error
                ) {

                    Log.e(
                        "PartenaireFoyer",
                        "Erreur evaluateJavascript FCM",
                        error
                    );
                }
            }
        );
    }


    @Override
public void onResume() {

        super.onResume();


        /*
         * Très important :
         *
         * si la page était encore en chargement
         * lors du lancement initial, on retente
         * quand l'utilisateur revient dans l'app.
         */
        if (
            pfFcmToken != null &&
            !pfFcmToken.trim().isEmpty()
        ) {

            pfPushHandler.postDelayed(
                () -> sendFcmTokenToWebsite(
                    pfFcmToken
                ),
                1500
            );

        } else {

            FirebaseMessaging
                .getInstance()
                .getToken()
                .addOnCompleteListener(
                    task -> {

                        if (
                            task.isSuccessful() &&
                            task.getResult() != null &&
                            !task.getResult()
                                .trim()
                                .isEmpty()
                        ) {

                            pfFcmToken =
                                task.getResult()
                                    .trim();

                            pfPushHandler.postDelayed(
                                () ->
                                    sendFcmTokenToWebsite(
                                        pfFcmToken
                                    ),
                                1500
                            );
                        }
                    }
                );
        }
    }

'''


text = (
    text[:class_end]
    + bridge
    + text[class_end:]
)


# ------------------------------------------------------------
# APPELER FCM APRÈS super.onCreate()
# ------------------------------------------------------------

target = (
    "super.onCreate(savedInstanceState);"
)


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

    class_match = re.search(
        r"public\s+class\s+MainActivity[^{]*\{",
        text
    )

    if not class_match:
        raise SystemExit(
            "Classe MainActivity introuvable"
        )


    on_create = r'''

    @Override
    public void onCreate(
        Bundle savedInstanceState
    ) {

        super.onCreate(
            savedInstanceState
        );

        initPartenaireFoyerPush();
    }

'''


    insert_at = (
        class_match.end()
    )


    text = (
        text[:insert_at]
        + on_create
        + text[insert_at:]
    )


path.write_text(
    text
)


print(
    "MainActivity FCM configurée :",
    path
)

PY


# ============================================================
# 4. PERMISSION ANDROID 13+
# ============================================================

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

    if "<application" not in text:
        raise SystemExit(
            "Balise <application> introuvable"
        )

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


# ============================================================
# 5. VERIFICATION DU BRIDGE
# ============================================================

echo ""
echo "Vérification du bridge FCM..."

grep -R \
  "PF_NATIVE_FCM_BRIDGE" \
  "$MAIN_DIR"

grep -R \
  "__PF_FCM_TOKEN__" \
  "$MAIN_DIR"

grep -R \
  "pf-native-fcm-token" \
  "$MAIN_DIR"

grep -R \
  "FirebaseMessaging" \
  "$MAIN_DIR"

echo ""
echo "=========================================="
echo " PUSH FIREBASE CONFIGURÉ"
echo "=========================================="
