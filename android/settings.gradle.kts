pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            val localProperties = file("local.properties")
            if (localProperties.exists()) {
                localProperties.inputStream().use { properties.load(it) }
            }
            val propertyPath = properties.getProperty("flutter.sdk")
            val envPath = System.getenv("FLUTTER_ROOT") ?: System.getenv("FLUTTER_HOME")
            require(!propertyPath.isNullOrBlank() || !envPath.isNullOrBlank()) {
                "flutter.sdk not set in local.properties or FLUTTER_ROOT/FLUTTER_HOME"
            }
            propertyPath ?: envPath!!
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
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
