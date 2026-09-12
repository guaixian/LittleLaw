import java.io.File
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 发布签名:本地读 android/key.properties(已 gitignore),
// CI 读环境变量(KEYSTORE_FILE/KEYSTORE_PASSWORD/KEY_ALIAS/KEY_PASSWORD)。
// 统一发布密钥,保证任何渠道产出的 APK 签名一致,覆盖安装不丢数据。
val keystoreProperties = Properties()
val keyPropertiesFile = File(rootDir, "key.properties")
if (keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val envKeystoreFile = System.getenv("KEYSTORE_FILE")
val hasReleaseSigning = keyPropertiesFile.exists() ||
    (envKeystoreFile != null && File(envKeystoreFile).exists())

android {
    namespace = "dev.littlelaw.littlelaw"
    // 本机 Android SDK 平台为 android-36;Flutter 3.44 默认 compileSdk=37 会缺包。
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        create("release") {
            if (keyPropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = File(rootDir, keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            } else {
                keyAlias = System.getenv("KEY_ALIAS") ?: "littlelaw"
                keyPassword = System.getenv("KEY_PASSWORD")
                storeFile = envKeystoreFile?.let { File(it) }
                storePassword = System.getenv("KEYSTORE_PASSWORD")
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.littlelaw.littlelaw"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // 有发布密钥用发布签名;没有则回退 debug 签名(可编译,不可发布)。
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
