group = "com.funtap.global.sdk.flutter"
version = "1.0.0"

buildscript {
    val kotlinVersion = "2.2.0" // khớp Kotlin metadata của fgsdk-release.aar
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.7.3")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Lõi SDK phát hành dạng AAR. KHÔNG dùng `implementation(files("libs/x.aar"))` được:
// AGP cấm local .aar trong module library (`hasLocalAarDeps`) vì AAR kết quả sẽ thiếu
// class/resource của nó. Cách chuẩn: dựng repo maven CỤC BỘ ngay trong plugin.
//
// ⚠️ Phải khai cho CẢ :app nữa, không chỉ riêng plugin: Gradle resolve transitive
// dependency bằng repositories của project TIÊU THỤ (:app), nên nếu chỉ khai ở đây
// thì :app báo "Could not find com.funtap.global.sdk:fgsdk". Đăng ký lên mọi project
// để game khỏi phải tự sửa build.gradle.
val fgsdkLocalRepo = projectDir.resolve("libs")
rootProject.allprojects {
    repositories {
        maven { url = fgsdkLocalRepo.toURI() }
    }
}

plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.funtap.global.sdk.flutter"

    // AAR build ở compileSdk 34; giữ 34 để khớp (xem CHANGELOG "targetSdk vs compileSdk").
    compileSdk = 34

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") { java.srcDirs("src/main/kotlin") }
    }

    defaultConfig {
        minSdk = 24 // fgsdk-release.aar yêu cầu >= 24

        // AdMob SDK đọc app id từ manifest lúc init.
        //
        // ⚠️ meta-data ${FGSDK_ADMOB_APP_ID} nằm trong manifest của CHÍNH plugin này, mà AGP
        // thay placeholder bằng giá trị của module sở hữu manifest — nên đặt giá trị ở
        // app/build.gradle của game là VÔ TÁC DỤNG (default dưới đây sẽ đè lên).
        // => Nguồn sự thật là property `FGSDK_ADMOB_APP_ID` trong android/gradle.properties,
        //    do CLI fetch-config-flutter ghi. Đọc ở đây thì mới thắng.
        // Thiếu property → dùng app id TEST của Google (build/chạy được, KHÔNG crash) —
        // nhưng bản release để nguyên TEST thì quảng cáo KHÔNG ra tiền.
        manifestPlaceholders["FGSDK_ADMOB_APP_ID"] =
            (project.findProperty("FGSDK_ADMOB_APP_ID") as? String)?.takeIf { it.isNotBlank() }
                ?: "ca-app-pub-3940256099942544~3347511713"
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Lõi SDK (bytecode) — dùng CHUNG với 2 package Cocos.
    // Nằm ở libs/com/funtap/global/sdk/fgsdk/<ver>/ (repo maven cục bộ khai ở trên).
    // `api` chứ không `implementation`: app phải thấy được class FGSDK/FGBridgeCore.
    api("com.funtap.global.sdk:fgsdk:3.2.6@aar")
}

// Third-party deps mà AAR cần nhưng không gói kèm (Firebase/MAX/AdMob/AppsFlyer/Billing…).
apply(from = "fgsdk-deps.gradle")
