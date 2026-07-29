plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.wolfcasaba.strumsight"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications (round 80) uses java.time — needs
        // core library desugaring on Android.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // StrumSight application ID (SDD Ch2, Kör 2 / ADR 0051). Changing it
        // makes the app install as a NEW app next to any older pre-rename
        // build already on a device — accepted before the store release.
        applicationId = "com.wolfcasaba.strumsight"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Debug keys for now so `flutter run --release` works. Production
            // signing is the job of SDD Ch2, Kör 14 (Flutter CI és release
            // pipeline) — a production release must NOT ship debug signing.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
