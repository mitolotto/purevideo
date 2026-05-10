pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.10.1" apply false
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") version("4.3.15") apply false
    id("com.google.firebase.crashlytics") version("2.8.1") apply false
    // END: FlutterFire Configuration
    // Bumped to 2.3.21 so the Kotlin compiler matches the stdlib
    // transitively pulled in by recent plugins (notably
    // screen_brightness_android-2.1.4, which depends on
    // kotlin-stdlib-2.3.21). Keeping the compiler on 2.1.x produced:
    //   "The binary version of kotlin-stdlib is 2.3.21 but the
    //    compiler version is 2.1.0 - please upgrade the Kotlin plugin."
    id("org.jetbrains.kotlin.android") version "2.3.21" apply false
}

include(":app")
