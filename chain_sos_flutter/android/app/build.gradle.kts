plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.chain_sos_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.chain_sos_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
    
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}


flutter {
    source = "../.."
}

// Copy the Flutter-built APKs to a predictable location after assemble tasks
val flutterApkDir = file("${rootDir}/../build/app/outputs/flutter-apk")
val hostApkOut = file("${rootDir}/../build/host/outputs/apk")
// Standard Gradle release output directory used by AGP
val gradleReleaseOut = file("$buildDir/outputs/apk/release")

// Populate Flutter's expected APK directory from the standard Gradle outputs
tasks.register<Copy>("populateFlutterApkDirFromGradleRelease") {
    from(gradleReleaseOut) {
        include("*.apk")
    }
    into(flutterApkDir)
    doFirst { flutterApkDir.mkdirs() }
    onlyIf { gradleReleaseOut.exists() }
}

tasks.register<Copy>("copyDebugFlutterApk") {
    val src = file("$flutterApkDir/app-debug.apk")
    from(src)
    into(hostApkOut)
    doFirst { hostApkOut.mkdirs() }
    onlyIf { src.exists() }
}

tasks.register<Copy>("copyReleaseFlutterApk") {
    val src = file("$flutterApkDir/app-release.apk")
    from(src)
    into(hostApkOut)
    doFirst { hostApkOut.mkdirs() }
    onlyIf { src.exists() }
}

// Ensure the release APK is first populated into Flutter's expected directory
// before attempting to copy it to the host output.
tasks.named<Copy>("copyReleaseFlutterApk").configure {
    dependsOn("populateFlutterApkDirFromGradleRelease")
}

tasks.matching { it.name == "assembleDebug" }.configureEach {
    finalizedBy("copyDebugFlutterApk")
}

tasks.matching { it.name == "assembleRelease" }.configureEach {
    finalizedBy("populateFlutterApkDirFromGradleRelease")
    finalizedBy("copyReleaseFlutterApk")
}
