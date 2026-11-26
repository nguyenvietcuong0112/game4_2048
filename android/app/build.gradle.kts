import java.text.SimpleDateFormat
import java.util.Date
import java.io.FileInputStream
import java.util.Properties
import com.android.build.gradle.internal.api.BaseVariantOutputImpl

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("dev.flutter.flutter-gradle-plugin")
    id("applovin-quality-service")
}

applovin {
    apiKey = "qRZzTMEyyQ0xxLqyERK6esE2su_KcIIRQ1FAqWCTxoo0bTSiVBtIwzyHEEmQd4WdqgOU8BkmP2M7isrUS50p4f"
}

android {
    namespace = "com.fw.water.block.number.merge"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.fw.water.block.number.merge"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = 102
        versionName = "1.0.2"
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            val storeFilePath = keystoreProperties["storeFile"] as String?
            storeFile = if (storeFilePath != null) rootProject.file(storeFilePath) else null
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    packaging {
        jniLibs {
            excludes += listOf("**/libapplovin-native-crash-reporter.so")
        }
    }

    applicationVariants.all {
        val variant = this
        outputs.all {
            val output = this
            if (output is BaseVariantOutputImpl) {
                val date = SimpleDateFormat("yyyyMMdd").format(Date())
                val vName = variant.versionName ?: flutter.versionName
                val vCode = variant.versionCode ?: flutter.versionCode
                output.outputFileName = "FW37_Mobgame_v${vName}_c${vCode}_${date}.apk"
            }
        }
    }
}

fun generateBuildInfo(targetDir: File) {
    try {
        val rootDir = rootProject.rootDir.parentFile
        val scriptFile = File(rootDir, "funtap_global_sdk/tools/fg-build-info.js")
        if (scriptFile.exists()) {
            val process = ProcessBuilder(
                "node",
                scriptFile.absolutePath,
                "--project", rootDir.absolutePath,
                "--engine", "flutter",
                "--platform", "android",
                "--pkg-version", "funtap-global-sdk-flutter 1.0.5",
                "--out", targetDir.absolutePath
            ).redirectErrorStream(true).start()
            val output = process.inputStream.bufferedReader().readText()
            process.waitFor()
            println(output.trim())
        }
    } catch (e: Exception) {
        println("[build-info] Auto-generate note: ${e.message}")
    }
}

tasks.matching { it.name == "assembleRelease" }.configureEach {
    doLast {
        val apkReleaseDir = layout.buildDirectory.dir("outputs/apk/release").get().asFile
        if (apkReleaseDir.exists()) {
            generateBuildInfo(apkReleaseDir)
        }
        val flutterApkDir = layout.buildDirectory.dir("outputs/flutter-apk").get().asFile
        if (flutterApkDir.exists()) {
            generateBuildInfo(flutterApkDir)
        }
    }
}

tasks.matching { it.name.startsWith("bundle") && it.name.endsWith("Bundle") }.configureEach {
    doLast {
        val date = SimpleDateFormat("yyyyMMdd").format(Date())
        val vName = android.defaultConfig.versionName ?: flutter.versionName
        val vCode = android.defaultConfig.versionCode ?: flutter.versionCode
        val bundleDir = layout.buildDirectory.dir("outputs/bundle").get().asFile
        if (bundleDir.exists()) {
            bundleDir.walkTopDown().filter { it.extension == "aab" }.forEach { aabFile ->
                if (!aabFile.name.startsWith("FW37_Mobgame")) {
                    val targetName = "FW37_Mobgame_v${vName}_c${vCode}_${date}.aab"
                    val targetFile = File(aabFile.parentFile, targetName)
                    aabFile.copyTo(targetFile, overwrite = true)
                }
            }
            generateBuildInfo(bundleDir)
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")

    // AppLovin MAX Mediation Adapters (14 networks for Game Client)
    implementation("com.applovin.mediation:google-adapter:+")
    implementation("com.applovin.mediation:google-ad-manager-adapter:+")
    implementation("com.applovin.mediation:facebook-adapter:+")
    implementation("com.applovin.mediation:mintegral-adapter:+")
    implementation("com.applovin.mediation:unityads-adapter:+")
    implementation("com.applovin.mediation:fyber-adapter:+")
    implementation("com.applovin.mediation:vungle-adapter:+")
    implementation("com.applovin.mediation:bytedance-adapter:+")
    implementation("com.applovin.mediation:ironsource-adapter:+")
    implementation("com.applovin.mediation:inmobi-adapter:+")
    implementation("com.applovin.mediation:yandex-adapter:+")
    implementation("com.applovin.mediation:bigoads-adapter:+")
    implementation("com.applovin.mediation:bidmachine-adapter:+")
    implementation("com.applovin.mediation:moloco-adapter:+")
}
