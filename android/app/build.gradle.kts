plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

dependencies {
    implementation("androidx.activity:activity-ktx:1.9.3")
    implementation("androidx.fragment:fragment-ktx:1.8.5")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-process:2.8.7")
    implementation("androidx.multidex:multidex:2.0.1")
    implementation("com.getkeepsafe.relinker:relinker:1.4.5")
}

// Exclude ABI jars - libflutter.so is provided via jniLibs directly
configurations.all {
    exclude(group = "io.flutter", module = "armeabi_v7a_debug")
    exclude(group = "io.flutter", module = "armeabi_v7a_profile")
    exclude(group = "io.flutter", module = "armeabi_v7a_release")
    exclude(group = "io.flutter", module = "arm64_v8a_debug")
    exclude(group = "io.flutter", module = "arm64_v8a_profile")
    exclude(group = "io.flutter", module = "arm64_v8a_release")
    exclude(group = "io.flutter", module = "x86_64_debug")
    exclude(group = "io.flutter", module = "x86_64_profile")
    exclude(group = "io.flutter", module = "x86_64_release")
    exclude(group = "io.flutter", module = "x86_debug")
    exclude(group = "io.flutter", module = "x86_profile")
    exclude(group = "io.flutter", module = "x86_release")
}

android {
    namespace = "com.nexus.v2"
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.nexus.v2"
        minSdk = 24
        targetSdk = 35
        versionCode = 4
        versionName = "1.0.4"
        multiDexEnabled = true
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
