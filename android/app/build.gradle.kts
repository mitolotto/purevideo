import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "io.github.majusss.purevideo"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Use the upstream applicationId so Firebase's
        // google-services.json (bundled in the repo) matches. If the
        // install fails on TV because an upstream build is already
        // installed with a different signing key, uninstall that first.
        applicationId = "io.github.majusss.purevideo"
        // Min SDK 21 (Android 5.0) is the minimum for the Leanback
        // launcher to recognize the app as an Android TV app.
        minSdk = maxOf(flutter.minSdkVersion, 21)
        // Pin targetSdk to 34 (Android 14) — same level as the target
        // device (Homatics Box R 4K Plus runs Android TV 14). Using a
        // higher targetSdk than the device's OS can trip "app not
        // compatible" checks on strict vendors.
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"]?.toString()
            keyPassword = keystoreProperties["keyPassword"]?.toString()
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"]?.toString()
            // Explicitly enable every modern APK signature scheme.
            // Android 14 TV boxes reject APKs that only ship v1 (JAR
            // signing) in some firmware variants. AGP by default keeps
            // v1+v2 enabled, but v3 and v4 are opt-in — we force them
            // on so the APK works on the widest range of TV firmwares.
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
            enableV4Signing = true
        }
    }

    buildTypes {
        release {
            if (keystoreProperties.containsKey("storeFile")) {
                signingConfig = signingConfigs.getByName("release")
            }

            ndk {
                // Android TV boxes use arm64-v8a. We keep the APK small
                // by excluding every other ABI.
                abiFilters.add("arm64-v8a")
            }

            // Do NOT enable code shrinking / resource shrinking for this
            // Flutter app — it breaks media_kit and serious_python
            // native glue classes.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // Android 6.0+ expects native libraries (.so) to be extracted to the
    // data partition rather than kept compressed inside the APK. With
    // useLegacyPackaging=true some Android TV firmwares — including
    // Android TV 14 on Homatics — return an "app not compatible" install
    // error because they cannot mmap compressed natives. Setting it to
    // false is the modern Play Store default.
    packaging {
        jniLibs {
            useLegacyPackaging = false
        }
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.md",
                "META-INF/LICENSE-notice.md",
                "META-INF/NOTICE",
                "META-INF/NOTICE.md",
                "META-INF/*.kotlin_module",
                "META-INF/LICENSE.txt"
            )
        }
    }
}

flutter {
    source = "../.."
}
