//
//  FGInternalData.h — mirror KA/util/FGInternalData.kt (spec §6.4): chỉ 1 property IsRemoveAds.
//  Unity PlayerPrefs "FGRemoveAds" → NSUserDefaults, key VERBATIM.
//
#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FGInternalData : NSObject

@property (class, nonatomic) BOOL IsRemoveAds;

@end

NS_ASSUME_NONNULL_END
