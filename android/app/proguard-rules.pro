# Flutter Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# AppsFlyer
-keep class com.appsflyer.** { *; }
-keep public class com.google.android.gms.common.api.GoogleApiClient { *; }
-dontwarn com.appsflyer.**

# AppLovin MAX
-keep class com.applovin.** { *; }
-dontwarn com.applovin.**

# Facebook SDK
-keep class com.facebook.** { *; }
-dontwarn com.facebook.**

# Google Play Services & AdMob
-keep public class com.google.android.gms.ads.** { *; }
-keep public class com.google.ads.** { *; }
-keep class org.chromium.** { *; }
-dontwarn com.google.android.gms.ads.**
-dontwarn org.chromium.**

# Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# AndroidX & Billing
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**

# Google Play Core / Deferred Components (referenced by io.flutter.embedding)
-dontwarn com.google.android.play.core.**
-dontwarn io.flutter.embedding.**

# FGSDK (Funtap Global SDK)
-keep class com.funtap.** { *; }
-dontwarn com.funtap.**

# AndroidX Startup
-keep class androidx.startup.** { *; }
-keep class * extends androidx.startup.Initializer { *; }
-dontwarn androidx.startup.**

# AndroidX WorkManager (used by AppLovin, Ads, AppsFlyer)
-keep class androidx.work.** { *; }
-keep class androidx.work.impl.** { *; }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-dontwarn androidx.work.**

# AndroidX Room (used by WorkManager)
-keep class androidx.room.** { *; }
-keep class * extends androidx.room.RoomDatabase { *; }
-keep class * extends androidx.room.RoomDatabase$Callback { *; }
-dontwarn androidx.room.**

# Gson
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.google.gson.** { *; }
-keep class * implements com.google.gson.TypeAdapterFactory
-keep class * implements com.google.gson.JsonSerializer
-keep class * implements com.google.gson.JsonDeserializer

# Guava / ListenableFuture
-keep class com.google.common.util.concurrent.ListenableFuture { *; }
-dontwarn com.google.common.util.concurrent.ListenableFuture

# Flutter Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**


