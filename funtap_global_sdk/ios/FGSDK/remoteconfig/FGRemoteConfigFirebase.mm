//
//  FGRemoteConfigFirebase.mm — mirror KA/remoteconfig/FGRemoteConfigFirebase.kt (spec §10).
//  ⚠️ chỉ module này import FirebaseRemoteConfig.
//
#import "FGRemoteConfigFirebase.h"
#import "../util/FGSDKDefines.h"
#import "../util/FGMainThreadDispatcher.h"
#import "../event/FGEvent.h"
#include <atomic>

#if FIREBASE_REMOTECONFIG_ENABLE
#import <FirebaseRemoteConfig/FirebaseRemoteConfig.h>
#endif

static bool sRegistered = false;
static std::atomic<bool> sIsInitialize{false}; // Kotlin @Volatile

#if FIREBASE_REMOTECONFIG_ENABLE

static FIRRemoteConfig *sRc = nil;

// ── Getter (spec §10) ────────────────────────────────────────────────────────
// Ready: Int/Bool dùng source != DefaultValue; String dùng StringValue khác rỗng; else default.
// Chưa ready: trả default. GetJson (generic) chưa ready → nil (⚠️ quirk 17: bỏ qua default,
// deserialize T ở tầng wrapper FGEvent::RemoteConfig::GetJson).

static FIRRemoteConfigValue * _Nullable FGRCValue(NSString *key) {
    if (!sIsInitialize.load()) return nil;
    return sRc ? [sRc configValueForKey:key] : nil;
}

/** source != DefaultValue (STATIC/REMOTE đều tính là "có") — mirror Unity ValueSource.DefaultValue. */
static BOOL FGRCIsFromRemoteOrStatic(FIRRemoteConfigValue *v) {
    return v.source != FIRRemoteConfigSourceDefault;
}

static void FGRCFetchRemoteConfig() {
    @try {
        FIRRemoteConfig *cfg = sRc;
        if (cfg == nil) {
            cfg = [FIRRemoteConfig remoteConfig];
            sRc = cfg;
        }
        // TimeSpan.Zero — ép lấy mới, bỏ throttle (spec §10)
        [cfg fetchWithExpirationDuration:0
                       completionHandler:^(FIRRemoteConfigFetchStatus status, NSError * _Nullable error) {
            [FGMainThreadDispatcher enqueue:^{ // spec §14 — callback third-party về main
                if (status != FIRRemoteConfigFetchStatusSuccess) {
                    NSLog(@"[FGRemoteConfig] fetch fail: %@", error);
                    return;
                }
                // Kotlin: activate onComplete bất kể kết quả → isInitialize=true
                [cfg activateWithCompletion:^(BOOL changed, NSError * _Nullable activateError) {
                    [FGMainThreadDispatcher enqueue:^{
                        sIsInitialize.store(true);
                        FGEvent::RemoteConfig::OnRemoteConfigFetched.invoke(); // internal + public
                        NSLog(@"[FGRemoteConfig] RemoteConfig fetched + activated");
                    }];
                }];
            }];
        }];
    } @catch (id ex) {
        NSLog(@"[FGRemoteConfig] fetchRemoteConfig error: %@", ex);
    }
}

#endif // FIREBASE_REMOTECONFIG_ENABLE

static NSInteger FGRCGetInt(NSString *key, NSInteger defaultValue) {
#if FIREBASE_REMOTECONFIG_ENABLE
    FIRRemoteConfigValue *v = FGRCValue(key);
    if (v == nil) return defaultValue;
    // Kotlin asLong().toInt()
    return FGRCIsFromRemoteOrStatic(v) ? (NSInteger)v.numberValue.longLongValue : defaultValue;
#else
    return defaultValue;
#endif
}

static BOOL FGRCGetBool(NSString *key, BOOL defaultValue) {
#if FIREBASE_REMOTECONFIG_ENABLE
    FIRRemoteConfigValue *v = FGRCValue(key);
    if (v == nil) return defaultValue;
    return FGRCIsFromRemoteOrStatic(v) ? v.boolValue : defaultValue;
#else
    return defaultValue;
#endif
}

static NSString *FGRCGetString(NSString *key, NSString *defaultValue) {
#if FIREBASE_REMOTECONFIG_ENABLE
    FIRRemoteConfigValue *v = FGRCValue(key);
    if (v == nil) return defaultValue;
    NSString *s = v.stringValue;
    return (s.length > 0) ? s : defaultValue;
#else
    return defaultValue;
#endif
}

static NSString * _Nullable FGRCGetJson(NSString *key) {
#if FIREBASE_REMOTECONFIG_ENABLE
    FIRRemoteConfigValue *v = FGRCValue(key);
    if (v == nil) return nil; // chưa ready → nil (bỏ qua default — quirk 17)
    NSString *s = v.stringValue;
    return (s.length > 0) ? s : nil;
#else
    return nil;
#endif
}

// Wire facade luôn (kể cả guard tắt) → getter trả default, IsRemoteConfigReady=false.
static void FGRCWireFacade() {
    FGEvent::RemoteConfig::IsRemoteConfigReady = []() -> BOOL { return sIsInitialize.load(); };
    FGEvent::RemoteConfig::GetInt = [](NSString *key, NSInteger def) { return FGRCGetInt(key, def); };
    FGEvent::RemoteConfig::GetBool = [](NSString *key, BOOL def) { return FGRCGetBool(key, def); };
    FGEvent::RemoteConfig::GetString = [](NSString *key, NSString *def) { return FGRCGetString(key, def); };
    FGEvent::RemoteConfig::GetJson = [](NSString *key) { return FGRCGetJson(key); };
}

@implementation FGRemoteConfigFirebase

+ (void)register {
    if (sRegistered) return;
    sRegistered = true;

    FGRCWireFacade();

#if FIREBASE_REMOTECONFIG_ENABLE
    FGEvent::InitEvent::FirebaseInitComplete.add([] { FGRCFetchRemoteConfig(); });
    FGEvent::Network::OnNetworkRestored.add([] {
        if (!sIsInitialize.load()) FGRCFetchRemoteConfig();
    });
#else
    NSLog(@"[FGRemoteConfig] FIREBASE_REMOTECONFIG_ENABLE=false → RemoteConfig off");
#endif
}

@end
