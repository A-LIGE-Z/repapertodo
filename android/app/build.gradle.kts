import java.io.FileInputStream
import java.util.Properties

fun String.hasAndroidSigningControlCharacter(): Boolean =
    any { character ->
        character.code <= 0x1F || character.code in 0x7F..0x9F
    }

fun requireAndroidSigningPropertyValue(key: String, value: String?) {
    if (value != null && value.hasAndroidSigningControlCharacter()) {
        throw GradleException("Android signing property '$key' must not contain control characters.")
    }
}

fun requireAndroidStoreFileValue(storeFile: String) {
    requireAndroidSigningPropertyValue("storeFile", storeFile)
    if (storeFile.contains('*') || storeFile.contains('?')) {
        throw GradleException("Android signing storeFile must not contain wildcard characters.")
    }
    val segments = storeFile.split('/', '\\')
    if (segments.any { segment -> segment == "." || segment == ".." }) {
        throw GradleException("Android signing storeFile must not contain dot-segments.")
    }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { input ->
        keystoreProperties.load(input)
    }
}
val androidSigningKeys = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
)
val androidSigningValues = androidSigningKeys.associateWith { key ->
    val value = keystoreProperties.getProperty(key)
    requireAndroidSigningPropertyValue(key, value)
    value?.trim()
}
val releaseStoreFile = androidSigningValues["storeFile"]
    ?.takeIf { it.isNotEmpty() }
    ?.also { requireAndroidStoreFileValue(it) }
    ?.let { rootProject.file(it) }
val hasReleaseSigningConfig = androidSigningKeys
    .all { key -> androidSigningValues[key]?.isNotBlank() == true } &&
    releaseStoreFile?.isFile == true

android {
    namespace = "com.aligez.repapertodo"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.aligez.repapertodo"
        minSdk = 34
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        resourceConfigurations += listOf("zh", "en")
    }

    signingConfigs {
        if (hasReleaseSigningConfig) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = androidSigningValues["storePassword"]
                keyAlias = androidSigningValues["keyAlias"]
                keyPassword = androidSigningValues["keyPassword"]
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
                enableV4Signing = true
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigningConfig) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
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

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}
