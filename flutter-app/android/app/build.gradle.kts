import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "dev.chuk.betterbahn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications (Java 8+ APIs on older devices).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    val keystoreProperties = Properties()
    val keystoreFile = file("../key.properties")
    if (keystoreFile.exists()) {
        keystoreFile.inputStream().use { input ->
            keystoreProperties.load(input)
        }
    } else {
        // IMPORTANT: If this message appears, your key.properties file is not found.
        // Double-check its location: ~/git/Besser-Bahn/flutter-app/android/key.properties
        println("WARNING: key.properties file not found at ${keystoreFile.absolutePath}")
    }


    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?

            // --- THIS LINE IS MODIFIED ---
            // Construct the path directly using rootProject.file and getProperty for safety
            storeFile = file("../${keystoreProperties.getProperty("storeFile")}")

            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.chuk.betterbahn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Monotonic versionCode derived from the semantic version name, NOT the
        // pubspec build number (+N). The +N was reset 7 -> 1 at 2.0.0, which
        // pushed versionCode below 1.0.3's and made Android/updaters treat the
        // 2.x releases as older (issue #9). major*10000 + minor*100 + patch is
        // strictly increasing across semver and always exceeds the old codes.
        val semver = flutter.versionName.substringBefore("+").split(".")
        versionCode = (semver.getOrNull(0)?.toIntOrNull() ?: 0) * 10000 +
            (semver.getOrNull(1)?.toIntOrNull() ?: 0) * 100 +
            (semver.getOrNull(2)?.toIntOrNull() ?: 0)
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isShrinkResources = true
            isMinifyEnabled = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    dependenciesInfo {
        // Disables dependency metadata when building APKs (for IzzyOnDroid/F-Droid)
        includeInApk = false
        // Disables dependency metadata when building Android App Bundles (for Google Play)
        includeInBundle = false
    }

    packaging {
        // Compress dex + native libs in the APK (legacy packaging). Shrinks the
        // download by ~12 MB back into the original size range (issue #9). Libs
        // are extracted to disk on install (extractNativeLibs=true).
        dex.useLegacyPackaging = true
        jniLibs.useLegacyPackaging = true
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}