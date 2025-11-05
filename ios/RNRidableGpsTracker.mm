#import "RNRidableGpsTracker.h"
#import <CoreLocation/CoreLocation.h>
#import <React/RCTLog.h>
#import <React/RCTBridge.h>
#import <React/RCTEventEmitter.h>

#ifdef RCT_NEW_ARCH_ENABLED
#import <RNRidableGpsTrackerSpec/RNRidableGpsTrackerSpec.h>
#endif

@interface RNRidableGpsTracker () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *lastLocation;
@property (nonatomic, assign) BOOL isTracking;
@property (nonatomic, assign) CLLocationDistance distanceFilter;
@property (nonatomic, assign) CLLocationAccuracy desiredAccuracy;
@property (nonatomic, assign) BOOL hasListeners;
@end

@implementation RNRidableGpsTracker
{
    bool _hasListeners;
}

RCT_EXPORT_MODULE()

+ (BOOL)requiresMainQueueSetup
{
    return NO;
}

- (instancetype)init
{
    if (self = [super init]) {
        [self setupLocationManager];
        _hasListeners = NO;
    }
    return self;
}

- (void)setupLocationManager
{
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    self.locationManager.allowsBackgroundLocationUpdates = YES;
    self.locationManager.pausesLocationUpdatesAutomatically = NO;
    self.locationManager.showsBackgroundLocationIndicator = YES;
    self.distanceFilter = 0;
    self.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = self.distanceFilter;
    self.locationManager.desiredAccuracy = self.desiredAccuracy;
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"location", @"error", @"authorizationChanged"];
}

- (void)startObserving
{
    _hasListeners = YES;
}

- (void)stopObserving
{
    _hasListeners = NO;
}

RCT_EXPORT_METHOD(configure:(NSDictionary *)config
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    if (config[@"distanceFilter"]) {
        self.distanceFilter = [config[@"distanceFilter"] doubleValue];
        self.locationManager.distanceFilter = self.distanceFilter;
    }
    
    if (config[@"desiredAccuracy"]) {
        NSString *accuracy = config[@"desiredAccuracy"];
        if ([accuracy isEqualToString:@"high"]) {
            self.desiredAccuracy = kCLLocationAccuracyBest;
        } else if ([accuracy isEqualToString:@"medium"]) {
            self.desiredAccuracy = kCLLocationAccuracyNearestTenMeters;
        } else if ([accuracy isEqualToString:@"low"]) {
            self.desiredAccuracy = kCLLocationAccuracyHundredMeters;
        }
        self.locationManager.desiredAccuracy = self.desiredAccuracy;
    }
    
    if (config[@"allowsBackgroundLocationUpdates"]) {
        self.locationManager.allowsBackgroundLocationUpdates = [config[@"allowsBackgroundLocationUpdates"] boolValue];
    }
    
    if (config[@"showsBackgroundLocationIndicator"]) {
        self.locationManager.showsBackgroundLocationIndicator = [config[@"showsBackgroundLocationIndicator"] boolValue];
    }
    
    if (config[@"pausesLocationUpdatesAutomatically"]) {
        self.locationManager.pausesLocationUpdatesAutomatically = [config[@"pausesLocationUpdatesAutomatically"] boolValue];
    }
    
    if (config[@"activityType"]) {
        NSString *activityType = config[@"activityType"];
        if ([activityType isEqualToString:@"fitness"]) {
            self.locationManager.activityType = CLActivityTypeFitness;
        } else if ([activityType isEqualToString:@"automotiveNavigation"]) {
            self.locationManager.activityType = CLActivityTypeAutomotiveNavigation;
        } else if ([activityType isEqualToString:@"otherNavigation"]) {
            self.locationManager.activityType = CLActivityTypeOtherNavigation;
        } else {
            self.locationManager.activityType = CLActivityTypeOther;
        }
    }
    
    resolve(nil);
}

RCT_EXPORT_METHOD(start:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    CLAuthorizationStatus authStatus;
    if (@available(iOS 14.0, *)) {
        authStatus = self.locationManager.authorizationStatus;
    } else {
        authStatus = [CLLocationManager authorizationStatus];
    }
    
    if (authStatus == kCLAuthorizationStatusDenied || authStatus == kCLAuthorizationStatusRestricted) {
        reject(@"PERMISSION_DENIED", @"Location permission denied", nil);
        return;
    }
    
    self.isTracking = YES;
    [self.locationManager startUpdatingLocation];
    resolve(nil);
}

RCT_EXPORT_METHOD(stop:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    self.isTracking = NO;
    [self.locationManager stopUpdatingLocation];
    resolve(nil);
}

RCT_EXPORT_METHOD(getCurrentLocation:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    if (self.lastLocation) {
        resolve([self convertLocationToDict:self.lastLocation]);
    } else {
        reject(@"NO_LOCATION", @"No location available", nil);
    }
}

RCT_EXPORT_METHOD(checkStatus:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    CLAuthorizationStatus authStatus;
    if (@available(iOS 14.0, *)) {
        authStatus = self.locationManager.authorizationStatus;
    } else {
        authStatus = [CLLocationManager authorizationStatus];
    }
    
    NSString *status;
    switch (authStatus) {
        case kCLAuthorizationStatusAuthorizedAlways:
            status = @"authorizedAlways";
            break;
        case kCLAuthorizationStatusAuthorizedWhenInUse:
            status = @"authorizedWhenInUse";
            break;
        case kCLAuthorizationStatusDenied:
            status = @"denied";
            break;
        case kCLAuthorizationStatusRestricted:
            status = @"restricted";
            break;
        case kCLAuthorizationStatusNotDetermined:
            status = @"notDetermined";
            break;
        default:
            status = @"unknown";
            break;
    }
    
    NSDictionary *result = @{
        @"isRunning": @(self.isTracking),
        @"isAuthorized": @(authStatus == kCLAuthorizationStatusAuthorizedAlways || 
                          authStatus == kCLAuthorizationStatusAuthorizedWhenInUse),
        @"authorizationStatus": status
    };
    
    resolve(result);
}

RCT_EXPORT_METHOD(requestPermissions:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
{
    [self.locationManager requestAlwaysAuthorization];
    
    CLAuthorizationStatus authStatus;
    if (@available(iOS 14.0, *)) {
        authStatus = self.locationManager.authorizationStatus;
    } else {
        authStatus = [CLLocationManager authorizationStatus];
    }
    
    BOOL isAuthorized = (authStatus == kCLAuthorizationStatusAuthorizedAlways || 
                        authStatus == kCLAuthorizationStatusAuthorizedWhenInUse);
    resolve(@(isAuthorized));
}

RCT_EXPORT_METHOD(openLocationSettings)
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSURL *url = [NSURL URLWithString:UIApplicationOpenSettingsURLString];
        if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    });
}

RCT_EXPORT_METHOD(addListener:(NSString *)eventName)
{
    // This is required for RN built-in EventEmitter support
    _hasListeners = YES;
}

RCT_EXPORT_METHOD(removeListeners:(double)count)
{
    // This is required for RN built-in EventEmitter support
    _hasListeners = NO;
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    CLLocation *location = locations.lastObject;
    if (!location) return;
    
    self.lastLocation = location;
    
    if (self.isTracking && _hasListeners) {
        NSDictionary *locationDict = [self convertLocationToDict:location];
        [self sendEventWithName:@"location" body:locationDict];
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    RCTLogError(@"Location manager failed: %@", error.localizedDescription);
    
    if (_hasListeners) {
        [self sendEventWithName:@"error" body:@{
            @"code": @(error.code),
            @"message": error.localizedDescription
        }];
    }
}

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager
{
    CLAuthorizationStatus status;
    if (@available(iOS 14.0, *)) {
        status = manager.authorizationStatus;
    } else {
        status = [CLLocationManager authorizationStatus];
    }
    
    RCTLogInfo(@"Authorization status changed: %d", (int)status);
    
    if (_hasListeners) {
        NSString *statusString;
        switch (status) {
            case kCLAuthorizationStatusAuthorizedAlways:
                statusString = @"authorizedAlways";
                break;
            case kCLAuthorizationStatusAuthorizedWhenInUse:
                statusString = @"authorizedWhenInUse";
                break;
            case kCLAuthorizationStatusDenied:
                statusString = @"denied";
                break;
            case kCLAuthorizationStatusRestricted:
                statusString = @"restricted";
                break;
            case kCLAuthorizationStatusNotDetermined:
                statusString = @"notDetermined";
                break;
            default:
                statusString = @"unknown";
                break;
        }
        
        [self sendEventWithName:@"authorizationChanged" body:@{
            @"status": statusString
        }];
    }
}

#pragma mark - Helper

- (NSDictionary *)convertLocationToDict:(CLLocation *)location
{
    return @{
        @"latitude": @(location.coordinate.latitude),
        @"longitude": @(location.coordinate.longitude),
        @"altitude": @(location.altitude),
        @"accuracy": @(location.horizontalAccuracy),
        @"speed": @(location.speed >= 0 ? location.speed : 0),
        @"bearing": @(location.course >= 0 ? location.course : 0),
        @"timestamp": @([location.timestamp timeIntervalSince1970] * 1000)
    };
}

#ifdef RCT_NEW_ARCH_ENABLED
- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:
    (const facebook::react::ObjCTurboModule::InitParams &)params
{
    return std::make_shared<facebook::react::NativeRidableGpsTrackerSpecJSI>(params);
}
#endif

@end
