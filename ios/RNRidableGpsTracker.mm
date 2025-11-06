#import "RNRidableGpsTracker.h"
#import <CoreLocation/CoreLocation.h>
#import <React/RCTLog.h>

@interface RNRidableGpsTracker () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CLLocation *lastLocation;
@property (nonatomic, assign) BOOL isTracking;
@property (nonatomic, assign) CLLocationDistance distanceFilter;
@property (nonatomic, assign) CLLocationAccuracy desiredAccuracy;
@property (nonatomic, assign) BOOL hasListeners;
@property (nonatomic, strong) NSTimer *repeatLocationTimer;
@end

@implementation RNRidableGpsTracker

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
    self.hasListeners = YES;
    RCTLogInfo(@"[RNRidableGpsTracker] ✅ startObserving called - listeners are now active");
}

- (void)stopObserving
{
    self.hasListeners = NO;
    RCTLogInfo(@"[RNRidableGpsTracker] stopObserving called - listeners are now inactive");
}

RCT_EXPORT_METHOD(configure:(NSDictionary *)config
                  resolve:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
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
                  reject:(RCTPromiseRejectBlock)reject)
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
    
    RCTLogInfo(@"[RNRidableGpsTracker] Starting GPS tracking, hasListeners: %d", self.hasListeners);
    
    // 짧은 대기 시간 후 시작 (JS 리스너 등록 완료 보장)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.isTracking = YES;
        [self.locationManager startUpdatingLocation];
        [self startRepeatLocationUpdates];
        RCTLogInfo(@"[RNRidableGpsTracker] ✅ GPS tracking started, hasListeners: %d", self.hasListeners);
        resolve(nil);
    });
}

RCT_EXPORT_METHOD(stop:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    self.isTracking = NO;
    [self.locationManager stopUpdatingLocation];
    [self stopRepeatLocationUpdates];
    RCTLogInfo(@"[RNRidableGpsTracker] GPS tracking stopped");
    resolve(nil);
}

RCT_EXPORT_METHOD(getCurrentLocation:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    if (self.lastLocation) {
        resolve([self convertLocationToDict:self.lastLocation]);
    } else {
        reject(@"NO_LOCATION", @"No location available", nil);
    }
}

RCT_EXPORT_METHOD(checkStatus:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
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
                  reject:(RCTPromiseRejectBlock)reject)
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

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    CLLocation *location = locations.lastObject;
    if (!location) return;
    
    self.lastLocation = location;
    
    RCTLogInfo(@"[RNRidableGpsTracker] Location update: lat=%.6f, lng=%.6f, tracking=%d, hasListeners=%d",
               location.coordinate.latitude, location.coordinate.longitude, self.isTracking, self.hasListeners);
    
    if (self.isTracking && self.hasListeners) {
        [self sendEventWithName:@"location" body:[self convertLocationToDict:location]];
    } else if (self.isTracking && !self.hasListeners) {
        RCTLogWarn(@"[RNRidableGpsTracker] ⚠️ Location update received but no listeners registered");
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    RCTLogError(@"[RNRidableGpsTracker] Location manager failed: %@", error.localizedDescription);
    
    if (self.hasListeners) {
        [self sendEventWithName:@"error" body:@{
            @"code": @(error.code),
            @"message": error.localizedDescription
        }];
    } else {
        RCTLogWarn(@"[RNRidableGpsTracker] Error occurred but no listeners registered");
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
    
    RCTLogInfo(@"[RNRidableGpsTracker] Authorization status changed: %d", (int)status);
    
    if (self.hasListeners) {
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
    } else {
        RCTLogWarn(@"[RNRidableGpsTracker] Authorization changed but no listeners registered");
    }
}

#pragma mark - Repeat Location Updates

- (void)startRepeatLocationUpdates
{
    [self stopRepeatLocationUpdates];
    
    RCTLogInfo(@"[RNRidableGpsTracker] Starting repeat location updates (1 second interval)");
    
    // 메인 스레드에서 타이머 생성
    dispatch_async(dispatch_get_main_queue(), ^{
        self.repeatLocationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                                    target:self
                                                                  selector:@selector(repeatLocationUpdate:)
                                                                  userInfo:nil
                                                                   repeats:YES];
    });
}

- (void)stopRepeatLocationUpdates
{
    if (self.repeatLocationTimer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.repeatLocationTimer invalidate];
            self.repeatLocationTimer = nil;
            RCTLogInfo(@"[RNRidableGpsTracker] Stopped repeat location updates");
        });
    }
}

- (void)repeatLocationUpdate:(NSTimer *)timer
{
    // 마지막 위치가 있고 트래킹 중이며 리스너가 있으면 1초마다 전송
    if (self.lastLocation && self.isTracking && self.hasListeners) {
        [self sendEventWithName:@"location" body:[self convertLocationToDict:self.lastLocation]];
    } else if (self.lastLocation && self.isTracking && !self.hasListeners) {
        RCTLogWarn(@"[RNRidableGpsTracker] ⚠️ Repeat location update skipped - no listeners registered");
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

@end