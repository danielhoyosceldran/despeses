import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystoreProperties = keystorePropertiesFile.exists()
if (hasKeystoreProperties) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.dceldran.despeses"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.dceldran.despeses"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeystoreProperties) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // A release build MUST be signed with the real keystore. Falling back
            // to debug signing here used to produce a debug-signed AAB with no
            // warning, which Play rejects and which can never be updated by a
            // properly signed build. Debug signing is still allowed for local
            // release smoke-tests, but only when explicitly opted into with
            // `-PallowDebugSigningForRelease=true`.
            val allowDebugSigning =
                (project.findProperty("allowDebugSigningForRelease") as String?)
                    ?.toBoolean() == true
            signingConfig = when {
                hasKeystoreProperties -> signingConfigs.getByName("release")
                allowDebugSigning -> {
                    logger.warn(
                        "WARNING: signing the release build with the DEBUG key " +
                            "(allowDebugSigningForRelease). This artifact must not be published."
                    )
                    signingConfigs.getByName("debug")
                }
                else -> throw GradleException(
                    "Cannot sign the release build: android/key.properties is missing. " +
                        "Create it with keyAlias/keyPassword/storeFile/storePassword, or pass " +
                        "-PallowDebugSigningForRelease=true for a local, non-publishable build."
                )
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
