//
//  OpenAppAction.h — mirror KA/ads/OpenAppAction.kt (spec §7.5). Thứ tự verbatim.
//  NONE=chưa có action; ATT/Ads/Review/AO = action chặn AppOpen hiển thị nhầm khi app quay lại foreground.
//
#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, OpenAppAction) {
    OpenAppActionNONE = 0,
    OpenAppActionATT,
    OpenAppActionAds,
    OpenAppActionReview,
    OpenAppActionAO,
};
