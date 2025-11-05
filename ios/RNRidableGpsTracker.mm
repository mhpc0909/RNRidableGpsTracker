#import "RNRidableGpsTracker.h"
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>
#import <CoreLocation/CoreLocation.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import <RNRidableGpsTrackerSpec/RNRidableGpsTrackerSpec.h>
#endif

@interface RNRidableGpsTracker () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, assign) BOOL isTracking;
@property (nonatomic, strong) NSMutableDictionary *config;
@property (nonatomic, strong) RCTPromiseResolveBlock currentLocationResolve;
@property (nonatomic, strong) RCTPromiseRejectBlock currentLocationReject;
@property (nonatomic, assign) BOOL hasListeners;
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, strong) CLLocation *lastLocation;
@property (nonatomic, assign) BOOL useTimerMode;
@end

@implementation RNRidableGpsTracker

RCT_EXPORT_MODULE(RNRidableGpsTracker)

+ (BOOL)requiresMainQueueSetup {
    return YES;
}

- (instancetype)init {
    if (self = [super init]) {
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = self;
        _isTracking = NO;
        _hasListeners = NO;
        _useTimerMode = YES;
        _config = [NSMutableDictionary dictionary];
        
        // Default configuration - Optimized for cycling GPS tracking
        _config[@"distanceFilter"] = @(-1);
        _config[@"desiredAccuracy"] = @"high";
        _config[@"activityType"] = @"otherNavigation";
        _config[@"allowsBackgroundLocationUpdates"] = @YES;
        _config[@"showsBackgroundLocationIndicator"] = @YES;
        _config[@"pausesLocationUpdatesAutomatically"] = @NO;
        _config[@"interval"] = @1000;
        
        // Apply default settings immediately
        _locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        _locationManager.distanceFilter = kCLDistanceFilterNone;
        _locationManager.activityType = CLActivityTypeOtherNavigation;
        _locationManager.pausesLocationUpdatesAutomatically = NO;
        _locationManager.allowsBackgroundLocationUpdates = YES;
        if (@available(iOS 11.0, *)) {
            _locationManager.showsBackgroundLocationIndicator = YES;
        }
    }
    return self;
}

- (NSArray<NSString *> *)supportedEvents {
    return @[@"location", @"error", @"authorizationChanged"];
}

- (void)startObserving {
    _hasListeners = YES;
}

- (void)stopObserving {
    _hasListeners = NO;
}

RCT_EXPORT_METHOD(addListener:(NSString *)eventName) {
    // Keep track of listeners
}

RCT_EXPORT_METHOD(removeListeners:(double)count) {
    // Remove listeners
}

#pragma mark - Public Methods

RCT_EXPORT_METHOD(configure:(NSDictionary *)config
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    @try {
        [self.config addEntriesFromDictionary:config];
        
        NSNumber *distanceFilter = config[@"distanceFilter"] ?: self.config[@"distanceFilter"];
        double filterValue = [distanceFilter doubleValue];
        self.locationManager.distanceFilter = filterValue < 0 ? kCLDistanceFilterNone : filterValue;
        
        NSString *accuracy = config[@"desiredAccuracy"] ?: self.config[@"desiredAccuracy"];
        if ([accuracy isEqualToString:@"high"]) {
            self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        } else if ([accuracy isEqualToString:@"medium"]) {
            self.locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters;
        } else {
            self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
        }
        
        NSString *activityType = config[@"activityType"] ?: self.config[@"activityType"];
        if ([activityType isEqualToString:@"fitness"]) {
            self.locationManager.activityType = CLActivityTypeFitness;
        } else if ([activityType isEqualToString:@"automotiveNavigation"]) {
            self.locationManager.activityType = CLActivityTypeAutomotiveNavigation;
        } else if ([activityType isEqualToString:@"otherNavigation"]) {
            self.locationManager.activityType = CLActivityTypeOtherNavigation;
        } else {
            self.locationManager.activityType = CLActivityTypeOther;
        }
        
        NSNumber *allowsBackground = config[@"allowsBackgroundLocationUpdates"] ?: self.config[@"allowsBackgroundLocationUpdates"];
        self.locationManager.allowsBackgroundLocationUpdates = [allowsBackground boolValue];
        
        NSNumber *showsIndicator = config[@"showsBackgroundLocationIndicator"] ?: self.config[@"showsBackgroundLocationIndicator"];
        if (@available(iOS 11.0, *)) {
            self.locationManager.showsBackgroundLocationIndicator = [showsIndicator boolValue];
        }
        
        NSNumber *pausesAuto = config[@"pausesLocationUpdatesAutomatically"] ?: self.config[@"pausesLocationUpdatesAutomatically"];
        self.locationManager.pausesLocationUpdatesAutomatically = [pausesAuto boolValue];
        
        resolve(nil);
    } @catch (NSException *exception) {
        reject(@"CONFIG_ERROR", exception.reason, nil);
    }
}

RCT_EXPORT_METHOD(start:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    if (self.isTracking) {
        resolve(nil);
        return;
    }
    
    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = self.locationManager.authorizationStatus;
    } else {
        status = [CLLocationManager authorizationStatus];
    }
    
    if (status == kCLAuthorizationStatusAuthorizedAlways ||
        status == kCLAuthorizationStatusAuthorizedWhenInUse) {
        
        self.locationManager.pausesLocationUpdatesAutomatically = NO;
        self.locationManager.allowsBackgroundLocationUpdates = YES;
        if (@available(iOS 11.0, *)) {
            self.locationManager.showsBackgroundLocationIndicator = YES;
        }
        
        [self.locationManager startUpdatingLocation];
        self.isTracking = YES;
        
        if (self.useTimerMode) {
            NSNumber *intervalMs = self.config[@"interval"] ?: @1000;
            NSTimeInterval interval = [intervalMs doubleValue] / 1000.0;
            
            self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                                target:self
                                                              selector:@selector(sendTimedLocationUpdate)
                                                              userInfo:nil
                                                               repeats:YES];
            [[NSRunLoop mainRunLoop] addTimer:self.updateTimer forMode:NSRunLoopCommonModes];
        }
        
        resolve(nil);
    } else {
        reject(@"PERMISSION_DENIED", @"Location permission not granted", nil);
    }
}

RCT_EXPORT_METHOD(stop:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    if (!self.isTracking) {
        resolve(nil);
        return;
    }
    
    [self.locationManager stopUpdatingLocation];
    
    if (self.updateTimer) {
        [self.updateTimer invalidate];
        self.updateTimer = nil;
    }
    
    self.isTracking = NO;
    self.lastLocation = nil;
    resolve(nil);
}

RCT_EXPORT_METHOD(getCurrentLocation:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    self.currentLocationResolve = resolve;
    self.currentLocationReject = reject;
    
    [self.locationManager requestLocation];
}

RCT_EXPORT_METHOD(checkStatus:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = self.locationManager.authorizationStatus;
    } else {
        status = [CLLocationManager authorizationStatus];
    }
    
    NSString *authStatus = [self authorizationStatusToString:status];
    BOOL isAuthorized = (status == kCLAuthorizationStatusAuthorizedAlways ||
                        status == kCLAuthorizationStatusAuthorizedWhenInUse);
    
    NSDictionary *result = @{
        @"isRunning": @(self.isTracking),
        @"isAuthorized": @(isAuthorized),
        @"authorizationStatus": authStatus
    };
    
    resolve(result);
}

RCT_EXPORT_METHOD(requestPermissions:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject) {
    [self.locationManager requestAlwaysAuthorization];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        CLAuthorizationStatus status;
        if (@available(iOS 14.0, *)) {
            status = self.locationManager.authorizationStatus;
        } else {
            status = [CLLocationManager authorizationStatus];
        }
        
        BOOL granted = (status == kCLAuthorizationStatusAuthorizedAlways ||
                       status == kCLAuthorizationStatusAuthorizedWhenInUse);
        resolve(@(granted));
    });
}

RCT_EXPORT_METHOD(openLocationSettings) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *settingsURL = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        if ([[UIApplication sharedApplication] canOpenURL:settingsURL]) {
            [[UIApplication sharedApplication] openURL:settingsURL options:@{} completionHandler:nil];
        }
    });
}

#pragma mark - Timer Method

- (void)sendTimedLocationUpdate {
    if (self.lastLocation && self.isTracking && self.hasListeners) {
        NSDictionary *locationDict = [self locationToDictionary:self.lastLocation];
        [self sendEventWithName:@"location" body:locationDict];
    }
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *location = [locations lastObject];
    
    self.lastLocation = location;
    
    if (self.currentLocationResolve) {
        NSDictionary *locationDict = [self locationToDictionary:location];
        self.currentLocationResolve(locationDict);
        self.currentLocationResolve = nil;
        self.currentLocationReject = nil;
    }
    
    if (self.isTracking && self.hasListeners && !self.useTimerMode) {
        NSDictionary *locationDict = [self locationToDictionary:location];
        [self sendEventWithName:@"location" body:locationDict];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    if (self.currentLocationReject) {
        self.currentLocationReject(@"LOCATION_ERROR", error.localizedDescription, error);
        self.currentLocationResolve = nil;
        self.currentLocationReject = nil;
    }
    
    if (self.hasListeners) {
        [self sendEventWithName:@"error" body:@{
            @"code": @(error.code),
            @"message": error.localizedDescription
        }];
    }
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    if (self.hasListeners) {
        CLAuthorizationStatus status;
        if (@available(iOS 14.0, *)) {
            status = manager.authorizationStatus;
        } else {
            status = [CLLocationManager authorizationStatus];
        }
        
        [self sendEventWithName:@"authorizationChanged" body:@{
            @"status": [self authorizationStatusToString:status]
        }];
    }
}

#pragma mark - Helpers

- (NSDictionary *)locationToDictionary:(CLLocation *)location {
    return @{
        @"latitude": @(location.coordinate.latitude),
        @"longitude": @(location.coordinate.longitude),
        @"altitude": @(location.altitude),
        @"accuracy": @(location.horizontalAccuracy),
        @"speed": @(location.speed >= 0 ? location.speed : 0),
        @"bearing": @(location.course >= 0 ? location.course : 0),
        @"timestamp": @(location.timestamp.timeIntervalSince1970 * 1000)
    };
}

- (NSString *)authorizationStatusToString:(CLAuthorizationStatus)status {
    switch (status) {
        case kCLAuthorizationStatusNotDetermined:
            return @"notDetermined";
        case kCLAuthorizationStatusRestricted:
            return @"restricted";
        case kCLAuthorizationStatusDenied:
            return @"denied";
        case kCLAuthorizationStatusAuthorizedAlways:
            return @"authorizedAlways";
        case kCLAuthorizationStatusAuthorizedWhenInUse:
            return @"authorizedWhenInUse";
        default:
            return @"notDetermined";
    }
}

- (void)dealloc {
    if (self.updateTimer) {
        [self.updateTimer invalidate];
        self.updateTimer = nil;
    }
}

#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params {
    return std::make_shared<facebook::react::NativeRidableGpsTrackerSpecJSI>(params);
}
#endif

@end
