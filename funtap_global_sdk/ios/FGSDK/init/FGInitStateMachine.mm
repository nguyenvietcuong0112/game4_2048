//
//  FGInitStateMachine.mm — mirror KA/init/FGInitStateMachine.kt (spec §6.3).
//
#import "FGInitStateMachine.h"
#import "../event/FGEvent.h"
#include <atomic>
#include <mutex>

// Kotlin @Volatile → std::atomic; @Synchronized → mutex chung cho SetReady/CheckReady
static std::atomic<NSInteger> sState{FGInitStateNone};
static std::atomic<bool> sHasFiredReady{false};
static std::mutex sMutex;

@implementation FGInitStateMachine

+ (BOOL)IsReady {
    NSInteger s = sState.load();
    return (s & FGInitStateAnalystic) != 0 && (s & FGInitStateAds) != 0;
}

+ (BOOL)IsAnalysticReady {
    return (sState.load() & FGInitStateAnalystic) != 0;
}

+ (BOOL)IsMaxReady {
    return (sState.load() & FGInitStateAds) != 0;
}

+ (void)SetReady:(FGInitState)flag {
    std::lock_guard<std::mutex> lock(sMutex);
    sState.store(sState.load() | flag);
    [self checkReadyLocked];
}

+ (void)CheckReady {
    std::lock_guard<std::mutex> lock(sMutex);
    [self checkReadyLocked];
}

// thân CheckReady dùng chung — tránh re-lock (Kotlin @Synchronized reentrant, std::mutex thì không)
+ (void)checkReadyLocked {
    if ([self IsReady] && !sHasFiredReady.load()) {
        sHasFiredReady.store(true);
        FGEvent::InitEvent::OnSDKReady.invoke(); // fire ĐÚNG 1 lần (spec §6.3)
    }
}

@end
