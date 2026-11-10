//
//  FGAdsState.h — mirror KA/ads/FGAdsState.kt (spec §7.2). Giá trị int verbatim.
//
#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, FGAdsState) {
    FGAdsStateNotInitialized = 0,
    FGAdsStateInitializing   = 1,
    FGAdsStateReady          = 2,
    FGAdsStateDisabled       = 3,
    FGAdsStateFailed         = 4,
};
