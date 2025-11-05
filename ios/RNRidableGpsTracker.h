#ifdef RCT_NEW_ARCH_ENABLED
#import <RNRidableGpsTrackerSpec/RNRidableGpsTrackerSpec.h>

@interface RNRidableGpsTracker : NSObject <NativeRidableGpsTrackerSpec>
#else
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface RNRidableGpsTracker : RCTEventEmitter <RCTBridgeModule>

// Declare event emitter method
- (void)sendEventWithName:(nullable NSString *)eventName body:(nullable id)body;

#endif

@end
