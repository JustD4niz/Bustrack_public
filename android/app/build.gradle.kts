plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.practica.bus_track"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.practica.bus_track"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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

// --- Clave de Google Maps ---------------------------------------------------
// El manifiesto declara android:value="${mapsApiKey}" y el valor real se lee
// de `android/local.properties`, que está en .gitignore y por tanto no se
// publica. Añade ahí una línea con MAPS_API_KEY=...
//
// Si la propiedad no está, el placeholder queda vacío: el mapa se ve gris,
// pero `flutter build apk` termina igual.
//
// Se parsea a mano en vez de usar java.util.Properties para no necesitar
// imports: en un .kts `java` resuelve a la extensión de Java, no al paquete.
val mapsApiKey: String = run {
    val archivo = rootProject.file("local.properties")
    if (!archivo.exists()) {
        ""
    } else {
        archivo.readLines()
            .firstOrNull { it.trimStart().startsWith("MAPS_API_KEY=") }
            ?.substringAfter("MAPS_API_KEY=")
            ?.trim()
            ?: ""
    }
}

android.defaultConfig.manifestPlaceholders["mapsApiKey"] = mapsApiKey
