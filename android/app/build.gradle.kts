plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.omni_explorer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Requis par flutter_local_notifications 18+ (java.time backport).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.omni_explorer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    packaging {
        jniLibs {
            // fvp (lecteur vidéo) et ffmpeg-kit (éditeur multimédia) embarquent
            // chacun la runtime C++ du NDK : sans cette règle, mergeNativeLibs
            // échoue (« 2 files found with path lib/<abi>/libc++_shared.so »).
            // Une seule copie est gardée ; la runtime libc++ reste compatible
            // entre versions du NDK, mais lecture vidéo et export FFmpeg sont
            // à vérifier sur appareil après chaque mise à jour de ces paquets.
            pickFirsts += "lib/**/libc++_shared.so"
        }
    }

    buildTypes {
        release {
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")

            // Désactive le rétrécissement de code/ressources en release : R8
            // peut supprimer l'enregistrement natif des plugins (ex.
            // permission_handler), provoquant un MissingPluginException
            // silencieux — la demande de permissions échoue dans l'APK compilé
            // alors qu'elle fonctionne en debug. Si vous réactivez la
            // minification, conservez proguard-rules.pro pour garder les plugins.
            isMinifyEnabled = false
            isShrinkResources = false
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

dependencies {
    // Backport des API java.time pour minSdk < 26 (flutter_local_notifications).
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
