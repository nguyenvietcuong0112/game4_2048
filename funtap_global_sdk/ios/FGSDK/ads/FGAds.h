//
//  FGAds.h — mirror KA/ads/FGAds.kt (spec §7.1): facade (Kotlin object → class methods).
//  Wire toàn bộ FGEvent::Ads::* → orchestrator + quản openAppAction (spec §7.5).
//  Bus được wire ngay khi Initialize(orchestrator); orchestrator tự guard drop khi chưa Ready (spec §7.2).
//
#pragma once
#import <Foundation/Foundation.h>
#import "OpenAppAction.h"

NS_ASSUME_NONNULL_BEGIN

@class FGAdsOrchestrator;

@interface FGAds : NSObject

/// spec §7.5 — action gate AppOpen. Nguồn chân lý duy nhất; FGSDK.openAppAction & provider đọc/ghi ở đây.
@property (class, nonatomic) OpenAppAction openAppAction;

/// spec §7.1 — FGAdsController gọi sau khi tạo + initialize orchestrator.
+ (void)Initialize:(FGAdsOrchestrator *)orch;

@end

NS_ASSUME_NONNULL_END
