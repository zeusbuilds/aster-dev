plugins {
    id("com.android.application")
    id("com.android.built-in-kotlin")
    // The Flutter Gradle Plugin must be applied after the Android plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

val asterApplicationId = providers.gradleProperty("aster.applicationId").get()

// Both shipped wallet engines and Flutter must support every advertised ABI.
// Flutter's default target list includes 32-bit ARM; only the complete 64-bit
// intersection is distributable. A single-target build must exclude the other
// 64-bit transitive JNI libraries as well as all 32-bit libraries.
fun selectAsterNativeAbis(targetPlatforms: String): Set<String> {
    val platformAbis = mapOf(
        "android-arm" to "armeabi-v7a",
        "android-arm64" to "arm64-v8a",
        "android-x64" to "x86_64",
    )
    val platforms = targetPlatforms.split(",")
    require(platforms.all { it in platformAbis }) {
        "Aster received an unsupported Flutter target-platform."
    }
    val selected = platforms.map { platformAbis.getValue(it) }
        .filter { it in setOf("arm64-v8a", "x86_64") }.toSet()
    require(selected.isNotEmpty()) {
        "Aster requires android-arm64 or android-x64; RGB_L1 has no 32-bit runtime."
    }
    return selected
}

val asterSelectedNativeAbis = selectAsterNativeAbis(
    providers.gradleProperty("target-platform").orElse("android-arm64,android-x64").get(),
)
val asterExcludedNativeAbis = setOf("armeabi-v7a", "x86", "arm64-v8a", "x86_64") - asterSelectedNativeAbis

android {
    // Final package identity is release-owned and remains blocked by DEC-006.
    namespace = asterApplicationId
    // Android 17 requires API 37; Flutter 3.47 still defaults to API 36.
    compileSdk = 37
    buildToolsVersion = "36.0.0"
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = asterApplicationId
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters.addAll(asterSelectedNativeAbis)
        }
    }

    packaging {
        jniLibs.excludes.addAll(asterExcludedNativeAbis.map { "**/$it/**" })
    }

    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        getByName("profile") {
            applicationIdSuffix = ".profile"
            versionNameSuffix = "-profile"
        }
        release {
            // Candidate artifacts are intentionally unsigned. The release
            // pipeline must sign them with the approved key and verify its
            // fingerprint; PLAT-001 blocks distribution until then.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    testImplementation("junit:junit:4.13.2")
}
