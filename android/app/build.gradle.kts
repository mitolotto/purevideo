import java.util.Properties
import java.io.FileInputStream
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

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

    defaultConfig {
        applicationId = "io.github.majusss.purevideo"
        // Min SDK 21 (Android 5.0) is the minimum for the Leanback
        // launcher to recognize the app as an Android TV app.
        minSdk = maxOf(flutter.minSdkVersion, 21)
        // Pin targetSdk to 34 (Android 14) — matches the target
        // Android TV 14 device. Using a higher targetSdk than the
        // device's OS can trip "app not compatible" checks on strict
        // TV vendors.
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // NO abiFilters: serious_python ships libpyjni.so +
        // libpythonbundle.so in jniLibs for multiple ABIs. Filtering
        // here (or via --target-platform in CI) can cause Gradle to
        // pick a subset for which some plugin dependency has no
        // binary, producing an APK whose lib/<abi>/ is empty and
        // bricking install with INSTALL_FAILED_NO_MATCHING_ABIS.
        // A fat APK (~180 MB) is the safe default — see PR #7.
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"]?.toString()
            keyPassword = keystoreProperties["keyPassword"]?.toString()
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"]?.toString()
            // Enable every modern APK signature scheme explicitly.
            // Android 14 TV boxes reject sideloaded APKs that ship
            // only v1 (JAR signing) in some firmware variants. AGP
            // keeps v1+v2 enabled by default — v3 and v4 are opt-in.
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

            // Do NOT enable code shrinking / resource shrinking for
            // this Flutter app — it breaks media_kit native glue and,
            // more importantly, strips libpython symbols that
            // serious_python's Python interpreter needs at runtime.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    // Packaging options — matches upstream (majusss/purevideo)
    // exactly. Two things matter here and both are required for
    // the embedded CPython to boot:
    //
    //   1. useLegacyPackaging = true keeps .so files inside the
    //      APK's lib/<abi>/ directory rather than extracting them
    //      to /data at install time. serious_python's JNI loader
    //      opens libpyjni.so / libpythonbundle.so from inside the
    //      APK. With useLegacyPackaging = false these files end up
    //      in a location the loader does not know about, producing
    //      "libpyjni.so not found" on every start.
    //
    //   2. doNotStrip("*/<abi>/libpython*.so") disables AGP's
    //      default strip pass over CPython. Stripping removes the
    //      exported symbol table that Python's own C-extension
    //      modules (ssl, hashlib, ctypes, ...) need at runtime via
    //      dlsym. A stripped libpython boots but then crashes the
    //      moment libresolveurl touches SSL, which is always.
    //
    // The older packagingOptions DSL is used on purpose: the new
    // packaging { jniLibs { useLegacyPackaging } ; resources { ... } }
    // block does not expose a doNotStrip counterpart in every AGP
    // 8.x version we have tried, so we stick with what is proven
    // to work upstream.
    packagingOptions {
        jniLibs {
            useLegacyPackaging = true
        }
        doNotStrip("*/arm64-v8a/libpython*.so")
        doNotStrip("*/armeabi-v7a/libpython*.so")
        doNotStrip("*/x86/libpython*.so")
        doNotStrip("*/x86_64/libpython*.so")
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

// Kotlin 2.3 removed the legacy string-typed `kotlinOptions` DSL.
// New DSL is the top-level `kotlin { compilerOptions }` extension
// with a strongly typed JvmTarget enum. See https://kotl.in/u1r8ln
kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
    }
}
