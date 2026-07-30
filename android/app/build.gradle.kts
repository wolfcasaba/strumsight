import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingPropertyNames = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)
val signingEnvironmentNames = mapOf(
    "storeFile" to "STRUMSIGHT_RELEASE_STORE_FILE",
    "storePassword" to "STRUMSIGHT_RELEASE_STORE_PASSWORD",
    "keyAlias" to "STRUMSIGHT_RELEASE_KEY_ALIAS",
    "keyPassword" to "STRUMSIGHT_RELEASE_KEY_PASSWORD",
)

fun completeSigningValues(
    source: String,
    values: Map<String, String?>,
): Map<String, String> {
    val missing = signingPropertyNames.filter { values[it].isNullOrBlank() }
    if (missing.isNotEmpty()) {
        throw GradleException(
            "Incomplete release signing configuration in $source; " +
                "missing ${missing.joinToString()}.",
        )
    }
    return values.mapValues { (_, value) -> value!! }
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val releaseSigningValues = if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    completeSigningValues(
        source = "android/key.properties",
        values = signingPropertyNames.associateWith { keystoreProperties.getProperty(it) },
    )
} else {
    val environmentValues = signingEnvironmentNames.mapValues { (_, environmentName) ->
        System.getenv(environmentName)
    }
    if (environmentValues.values.all { it.isNullOrBlank() }) {
        null
    } else {
        completeSigningValues(
            source = "release signing environment",
            values = environmentValues,
        )
    }
}

val releaseSigningRequired =
    System.getenv("STRUMSIGHT_REQUIRE_RELEASE_SIGNING")
        ?.equals("true", ignoreCase = true) == true
if (releaseSigningRequired && releaseSigningValues == null) {
    throw GradleException("Production release signing configuration is required.")
}

val releaseStoreFile = releaseSigningValues?.let { file(it.getValue("storeFile")) }
if (releaseStoreFile != null &&
    (!releaseStoreFile.isFile || releaseStoreFile.length() == 0L)
) {
    throw GradleException("The configured release signing keystore is missing or empty.")
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

    signingConfigs {
        if (releaseSigningValues != null) {
            create("release") {
                keyAlias = releaseSigningValues.getValue("keyAlias")
                keyPassword = releaseSigningValues.getValue("keyPassword")
                storeFile = requireNotNull(releaseStoreFile)
                storePassword = releaseSigningValues.getValue("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Local development remains zero-config; the production workflow
            // supplies complete signing values and requires release signing.
            signingConfig = if (releaseSigningValues == null) {
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }
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
