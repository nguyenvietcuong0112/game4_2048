//
//  FGInitStateMachine.h — mirror KA/init/FGInitStateMachine.kt (spec §6.3):
//  bitmask FGInitState (event/FGEventTypes.h). IsReady cần CẢ HAI cờ Analystic + Ads.
//  CheckReady fire FGEvent::InitEvent::OnSDKReady ĐÚNG 1 LẦN (guard hasFiredReady).
//  (Cờ Consent=4 tồn tại trong enum nhưng KHÔNG dùng ở đây.)
//
#pragma once
#import <Foundation/Foundation.h>
#import "../event/FGEventTypes.h"

#if !defined(__OBJC__)
#error "FGInitStateMachine.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGInitStateMachine : NSObject

+ (BOOL)IsReady;
+ (BOOL)IsAnalysticReady; // ⚠️ giữ typo `Analystic`
+ (BOOL)IsMaxReady;

/// Kotlin `SetReady(flag)` — state |= flag rồi CheckReady().
+ (void)SetReady:(FGInitState)flag;

+ (void)CheckReady;

@end

NS_ASSUME_NONNULL_END
