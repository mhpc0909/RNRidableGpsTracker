#import <React/RCTBridgeModule.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import <RNRidableGpsTrackerSpec/RNRidableGpsTrackerSpec.h>

@interface RNRidableGpsTracker : NSObject <NativeRidableGpsTrackerSpec>
#else

@interface RNRidableGpsTracker : NSObject <RCTBridgeModule>
#endif

@end
