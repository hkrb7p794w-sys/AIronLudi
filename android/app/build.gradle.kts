// Versionsnummer aus der CI (Laufnummer). Die bisherige Kotlin-App „IronLudi“ hat dieselbe Application-ID und
// zählte ab 1 – der Abstand 10 000 sorgt dafür, dass Android die Flutter-App als Update installiert.
val buildNumber = providers.environmentVariable("BUILD_NUMBER").orNull?.toIntOrNull() ?: 1
// Signaturschlüssel nur aus der CI (GitHub-Secrets), nie im Repo. Derselbe Schlüssel wie bei der Kotlin-App,
// sonst lehnt Android das Update ab. Ohne Schlüssel: Debug-Signatur.
val keystorePath = providers.environmentVariable("ANDROID_KEYSTORE_PATH").orNull
val keystorePassword = providers.environmentVariable("ANDROID_KEYSTORE_PASSWORD").orNull

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.hkrb7p794w.aironludi"
    // flutter_local_notifications, permission_handler und androidx.core 1.19 verlangen SDK 37 (abwärtskompatibel,
    // ändert nicht, auf welchen Geräten die App läuft – das bestimmt minSdk).
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // Gleiche ID wie die bisherige Android-App (Entscheidung vom 13.11.2026): ersetzt sie beim Update.
        applicationId = "io.github.hkrb7p794w.gym"
        // Health Connect und die bisherige App: Android 8.0.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = 10_000 + buildNumber
        versionName = "2.0.$buildNumber"
    }

    signingConfigs {
        if (keystorePath != null && keystorePassword != null) {
            create("release") {
                storeFile = file(keystorePath)
                storePassword = keystorePassword
                keyAlias = "ironludi"
                keyPassword = keystorePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // flutter_local_notifications nutzt java.time auch auf Android 8–13 (Core Library Desugaring).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
