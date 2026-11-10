//
//  FGAppLovinEventMapper.mm — mirror KA/tracking/applovin/FGAppLovinEventMapper.kt.
//
//  Mỗi FG event qua orchestrator được soi 1 lần; khớp 1 dòng sheet → phái sinh FGTrackingEvent
//  mới target providers=[AppLovin] với TÊN + PARAM theo cột AppLovin. KHÔNG đổi call-site game.
//
//  FG event  → AppLovin event:
//   - ad_impression             → ad_view [+ rewarded_ad_opportunity nếu ad_format=reward]
//   - ad_click                  → ad_click
//   - level_start               → level_start    (value = param "level")
//   - level_end (success=true)  → level_complete (value = param "level")
//   - resource_source           → virtual_resource_transaction (value=+amount, resource_type=name)
//   - resource_sink             → virtual_resource_transaction (value=-amount, resource_type=name)
//                                 [+ use_prop nếu type|item_type = booster]
//   - tut_action (name=success) → tutorial_complete
//   - init_sdk                  → app_open (1 lần/launch)
//
//  value/param AppLovin LUÔN String. Không map: game_shop_enter / login / sign_up (Dev tự gọi).
//  Guard đệ quy: bỏ qua event đã target AppLovin.
//
#import "FGAppLovinEventMapper.h"
#import "../../util/FGConstValue.h"
#include <algorithm>
#include <cmath>

/// providers=[AppLovin] cho mọi event phái sinh.
static const std::vector<ProviderType> kALProviders = { ProviderTypeAppLovin };

static NSString *FGStrParam(FGParams p, NSString *key) {
    id v = p[key];
    if (v == nil || v == (id)[NSNull null]) return nil;
    return [NSString stringWithFormat:@"%@", v];
}

/// value = ±amount (source +, sink -). NSNumber stringValue: 5.0→"5", 2.5→"2.5", -5→"-5".
static NSString *FGSignedAmount(NSString *_Nullable raw, BOOL positive) {
    double d = raw != nil ? raw.doubleValue : 0.0;
    double v = positive ? d : -d;
    return [@(v) stringValue];
}

static FGTrackingEvent *FGAL(NSString *name, FGParams _Nullable params) {
    return [[FGTrackingEvent alloc] initWithEventName:name params:params providers:kALProviders];
}

@implementation FGAppLovinEventMapper

+ (NSArray<FGTrackingEvent *> *)map:(FGTrackingEvent *)event {
    const std::vector<ProviderType> &provs = event.providers;
    if (std::find(provs.begin(), provs.end(), ProviderTypeAppLovin) != provs.end()) return @[];

    FGParams p = event.params;
    NSString *name = event.eventName;
    NSMutableArray<FGTrackingEvent *> *out = [NSMutableArray array];

    if ([name isEqualToString:@"ad_impression"]) {
        [out addObject:FGAL(@"ad_view", nil)];
        if ([FGStrParam(p, @"ad_format") isEqualToString:FGConstValue.Reward])
            [out addObject:FGAL(@"rewarded_ad_opportunity", nil)];
    } else if ([name isEqualToString:@"ad_click"]) {
        [out addObject:FGAL(@"ad_click", nil)];
    } else if ([name isEqualToString:@"level_start"]) {
        [out addObject:FGAL(@"level_start", @{ @"value": FGStrParam(p, @"level") ?: @"" })];
    } else if ([name isEqualToString:@"level_end"]) {
        if ([FGStrParam(p, @"success") isEqualToString:@"true"])
            [out addObject:FGAL(@"level_complete", @{ @"value": FGStrParam(p, @"level") ?: @"" })];
    } else if ([name isEqualToString:@"resource_source"]) {
        [out addObject:FGAL(@"virtual_resource_transaction", @{
            @"value": FGSignedAmount(FGStrParam(p, @"amount"), YES),
            @"resource_type": FGStrParam(p, @"name") ?: @"",
        })];
    } else if ([name isEqualToString:@"resource_sink"]) {
        [out addObject:FGAL(@"virtual_resource_transaction", @{
            @"value": FGSignedAmount(FGStrParam(p, @"amount"), NO),
            @"resource_type": FGStrParam(p, @"name") ?: @"",
        })];
        NSString *type = FGStrParam(p, @"type") ?: FGStrParam(p, @"item_type");
        if ([type isEqualToString:@"booster"]) [out addObject:FGAL(@"use_prop", nil)];
    } else if ([name isEqualToString:@"tut_action"]) {
        NSString *actionName = FGStrParam(p, @"name");
        if ([actionName isEqualToString:@"success"] || [actionName isEqualToString:@"tut_finish"])
            [out addObject:FGAL(@"tutorial_complete", nil)];
    } else if ([name isEqualToString:FGConstValue.InitSDK]) {
        [out addObject:FGAL(@"app_open", nil)];
    }

    return out;
}

@end
