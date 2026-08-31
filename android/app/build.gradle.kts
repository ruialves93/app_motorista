import java.io.File

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ruibarata.cctvmotorista"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

    defaultConfig {
        applicationId = "com.ruibarata.cctvmotorista"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode ?: 1
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Caminho absoluto direto com importação limpa de File
            storeFile = File("C:/Users/ruial/Documents/APK/app_motorista/android/app/my-release-key.jks")
            storePassword = "password123"
            keyAlias = "my-key-alias"
            keyPassword = "password123"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

flutter {
    source = "../.."
}