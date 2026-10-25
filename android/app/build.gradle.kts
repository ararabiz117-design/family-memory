plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key never belongs in this repository.  The release helper sets
// these process-scoped values after reading the locally protected key material.
val releaseStoreFile = providers.environmentVariable("FAMILY_MEMORY_ANDROID_STORE_FILE").orNull
val releaseStorePassword = providers.environmentVariable("FAMILY_MEMORY_ANDROID_STORE_PASSWORD").orNull
val releaseKeyAlias = providers.environmentVariable("FAMILY_MEMORY_ANDROID_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("FAMILY_MEMORY_ANDROID_KEY_PASSWORD").orNull
val releaseArtifactRequested = gradle.startParameter.taskNames.any { taskName ->
    val task = taskName.substringAfterLast(':')
    task.contains("Release", ignoreCase = true) &&
        (task.contains("assemble", ignoreCase = true) || task.contains("bundle", ignoreCase = true))
}

android {
    namespace = "jp.familymemory.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "jp.familymemory.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("playUpload") {
            if (!releaseStoreFile.isNullOrBlank()) {
                storeFile = file(releaseStoreFile)
            }
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            val hasPlayUploadKey = !releaseStoreFile.isNullOrBlank() &&
                !releaseStorePassword.isNullOrBlank() &&
                !releaseKeyAlias.isNullOrBlank() &&
                !releaseKeyPassword.isNullOrBlank()
            if (hasPlayUploadKey) {
                signingConfig = signingConfigs.getByName("playUpload")
            } else if (releaseArtifactRequested) {
                throw GradleException(
                    "A Play upload key is required. Run tool/build_android_play_aab.ps1; do not use the debug key for release.",
                )
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Japanese invitation OCR stays on-device; no image is sent to an OCR API.
    implementation("com.google.mlkit:text-recognition-japanese:16.0.1")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
