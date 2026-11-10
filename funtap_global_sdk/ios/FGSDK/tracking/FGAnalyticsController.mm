//
//  FGAnalyticsController.mm — mirror KA/tracking/FGAnalyticsController.kt (spec §9.1).
//
#import "FGAnalyticsController.h"
#import "FGTrackingEvent.h"
#import "FGTrackingOrchestrator.h"
#import "../event/FGEvent.h"
#include <vector>

// Kotlin object state (registered/orchestrator) → static nội bộ .mm
static BOOL sRegistered = NO;
static FGTrackingOrchestrator *sOrchestrator = nil;

@interface FGAnalyticsController ()
+ (void)wireFacade:(FGTrackingOrchestrator *)orch;
@end

@implementation FGAnalyticsController

+ (void)register {
    if (sRegistered) return;
    sRegistered = YES;

    FGTrackingOrchestrator *orch = [[FGTrackingOrchestrator alloc] init];
    sOrchestrator = orch;
    [self wireFacade:orch];

    FGEvent::Tracking::OnInitTracking.add([orch](BOOL isConsent, BOOL isATT) {
        [orch initialize:isConsent isATTAuthorized:isATT];
    });
}

+ (void)wireFacade:(FGTrackingOrchestrator *)orch {
    using namespace FGEvent;
    const std::vector<ProviderType> firebaseOnly { ProviderTypeFirebase };

    Tracking::LogEvent = [orch, firebaseOnly](NSString *name) {
        [orch logEvent:[[FGTrackingEvent alloc] initWithEventName:name params:nil providers:firebaseOnly]];
    };
    Tracking::LogEventWithParams = [orch, firebaseOnly](NSString *name, FGParams p) {
        [orch logEvent:[[FGTrackingEvent alloc] initWithEventName:name params:p providers:firebaseOnly]];
    };
    Tracking::LogEventProvider = [orch](NSString *name, ProviderType prov) {
        [orch logEvent:[[FGTrackingEvent alloc] initWithEventName:name params:nil
                                                        providers:std::vector<ProviderType>{ prov }]];
    };
    Tracking::LogEventProviders = [orch](NSString *name, std::vector<ProviderType> provs) {
        [orch logEvent:[[FGTrackingEvent alloc] initWithEventName:name params:nil providers:std::move(provs)]];
    };
    Tracking::LogEventWithProvider = [orch](NSString *name, FGParams p, ProviderType prov) {
        [orch logEvent:[[FGTrackingEvent alloc] initWithEventName:name params:p
                                                        providers:std::vector<ProviderType>{ prov }]];
    };
    Tracking::LogEventWithProviders = [orch](NSString *name, FGParams p, std::vector<ProviderType> provs) {
        [orch logEvent:[[FGTrackingEvent alloc] initWithEventName:name params:p providers:std::move(provs)]];
    };
    Tracking::SetUserProperties = [orch](FGParams props) { [orch setUserProperties:props]; };
    Tracking::SetConsent = [orch](BOOL isConsent) { [orch setConsent:isConsent]; };
}

@end
