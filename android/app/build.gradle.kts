import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

/// google-services が oauth_client を埋めないとき、CredentialManager 用の Web クライアント ID を
/// ビルド時に R.string.default_web_client_id へ入れる（google_sign_in が参照）。
/// google-services.json に client_type 3（Web）が含まれると、プラグイン側で
/// `default_web_client_id` が生成されるため、こちらの resValue と二重定義にならないようにする。
fun googleServicesJsonIncludesWebOAuthClient(): Boolean {
    val f = file("google-services.json")
    if (!f.exists()) return false
    val t = f.readText()
    if (Regex(""""oauth_client"\s*:\s*\[\s*\]""").containsMatchIn(t)) return false
    return """"client_type": 3""".toRegex().containsMatchIn(t)
}

/// Dart の [lib/config/google_web_client_id.dart] と値を揃えるための単一ソース（手元ではここを直す）。
fun readGoogleWebClientIdFromDartConfig(): String? {
    val dartFile = File(rootProject.projectDir, "../lib/config/google_web_client_id.dart")
    if (!dartFile.exists()) return null
    val m =
        Regex("""const\s+String\s+kGoogleOAuth2WebClientId\s*=\s*['"]([^'"]+)['"]""")
            .find(dartFile.readText())
            ?: return null
    return m.groupValues[1].trim().takeIf { it.isNotEmpty() }
}

fun readGoogleWebClientIdForResValue(): String? {
    System.getenv("GOOGLE_WEB_CLIENT_ID")?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
    val lp = File(rootProject.projectDir, "local.properties")
    if (lp.exists()) {
        val p = Properties()
        lp.inputStream().use { p.load(it) }
        sequenceOf(
                p.getProperty("googleWebClientId"),
                p.getProperty("GOOGLE_WEB_CLIENT_ID"),
                p.getProperty("google.web.client.id"),
            )
            .mapNotNull { it?.trim() }
            .firstOrNull { it.isNotEmpty() }
            ?.let { return it }
    }
    return readGoogleWebClientIdFromDartConfig()
}

/// `oauth_client` が空でないとき、JSON 内の Web クライアント IDが Dart 定数と一致することを保証する。
fun assertGoogleWebClientIdsAlignedWithDart() {
    val dartId = readGoogleWebClientIdFromDartConfig() ?: return
    val gs = file("google-services.json")
    if (!gs.exists()) return
    val t = gs.readText()
    if (Regex(""""oauth_client"\s*:\s*\[\s*\]""").containsMatchIn(t)) return
    if (!t.contains(dartId)) {
        throw GradleException(
            "google-services.json の oauth_client と lib/config/google_web_client_id.dart の " +
                "kGoogleOAuth2WebClientId が一致しません。\n" +
                "client_type 3 の client_id を Dart と同一の …apps.googleusercontent.com に更新してください。\n" +
                "Dart 側の値: $dartId",
        )
    }
}

// Firebase: android/app/google-services.json を置いたときだけ有効（無い環境でもビルド可能）
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// google-services.json に OAuth クライアントが無いと Google サインインが失敗する
fun checkGoogleServicesOauthClients() {
    val f = file("google-services.json")
    if (!f.exists()) return
    val t = f.readText()
    if (Regex(""""oauth_client"\s*:\s*\[\s*\]""").containsMatchIn(t)) {
        val hasResWebId = readGoogleWebClientIdForResValue() != null
        println(
            "WARNING: google-services.json の oauth_client が空です。" +
                if (hasResWebId) {
                    " GOOGLE_WEB_CLIENT_ID / local.properties / lib/config/google_web_client_id.dart により default_web_client_id が注入されます。"
                } else {
                    " Firebase で Android の SHA-1 を登録して JSON を取り直すか、" +
                        "lib/config/google_web_client_id.dart の kGoogleOAuth2WebClientId を設定するか、" +
                        "GOOGLE_WEB_CLIENT_ID または android/local.properties の googleWebClientId を設定してください。"
                },
        )
    }
}
checkGoogleServicesOauthClients()
assertGoogleWebClientIdsAlignedWithDart()

android {
    namespace = "com.auraface.kami_face_oracle"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // アプリケーションID（パッケージ名）
        applicationId = "com.auraface.kami_face_oracle"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        if (!googleServicesJsonIncludesWebOAuthClient()) {
            readGoogleWebClientIdForResValue()?.let { webId ->
                resValue("string", "default_web_client_id", webId)
            }
        }
    }

    signingConfigs {
        create("release") {
            // リリースビルド用の署名設定
            // 実際のリリース時は、キーストアファイルとパスワードを設定してください
            // storeFile = file("keystore.jks")
            // storePassword = System.getenv("KEYSTORE_PASSWORD") ?: ""
            // keyAlias = "key"
            // keyPassword = System.getenv("KEY_PASSWORD") ?: ""
        }
    }

    buildTypes {
        release {
            // リリースビルド用の署名設定（デバッグ時はデバッグキーを使用）
            signingConfig = signingConfigs.getByName("debug")
            // コードの難読化（オプション）
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
