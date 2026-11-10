//
//  FGTrackingOrchestrator.h — mirror KA/tracking/FGTrackingOrchestrator.kt (spec §9.1-9.2):
//  điều phối provider + buffer khi chưa Ready.
//  Đủ provider signal ready (kể cả init fail — quirk 20) → OnAllProvidersReady:
//  flush buffer + SetReady(Analystic) + fire FGEvent::Tracking::OnAllProvidersReady.
//  ⚠️ LogEvent & SetUserProperties buffer khi !Ready; SaveUserId KHÔNG buffer (quirk 14);
//  SetConsent không check state.
//
#pragma once
#import <Foundation/Foundation.h>
#import "FGTrackingEvent.h"
#import "../util/FGSDKDefines.h"

#if !defined(__OBJC__)
#error "FGTrackingOrchestrator.h là ObjC++ — chỉ include từ file .mm"
#endif

NS_ASSUME_NONNULL_BEGIN

@interface FGTrackingOrchestrator : NSObject

- (void)initialize:(BOOL)isConsent isATTAuthorized:(BOOL)isATTAuthorized;

- (void)logEvent:(FGTrackingEvent *)event;

- (void)setUserProperties:(FGParams)props;

/// spec §9.2 — SetConsent KHÔNG check state.
- (void)setConsent:(BOOL)isConsent;

@end

NS_ASSUME_NONNULL_END
