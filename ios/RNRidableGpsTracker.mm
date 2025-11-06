#import "RNRidableGpsTracker.h"
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <React/RCTLog.h>

@interface RNRidableGpsTracker () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CMAltimeter *altimeter;
@property (nonatomic, strong) CLLocation *lastLocation;
@property (nonatomic, strong) CMAltitudeData *lastAltitudeData;
@property (nonatomic, assign) BOOL isTracking;
@property (nonatomic, assign) CLLocationDistance distanceFilter;
@property (nonatomic, assign) CLLocationAccuracy desiredAccuracy;
@property (nonatomic, assign) BOOL hasListeners;
@property (nonatomic, strong) NSTimer *repeatLocationTimer;
@property (nonatomic, strong) NSDate *lastLocationTimestamp;
@property (nonatomic, assign) BOOL isNewLocationAvailable;

// 🆕 칼만 필터 관련
@property (nonatomic, assign) double startGpsAltitude;
@property (nonatomic, assign) BOOL hasStartGpsAltitude;
@property (nonatomic, assign) double enhancedAltitude;

// 🆕 가중치 (안드로이드와 동일)
@property (nonatomic, assign) double gpsWeight;
@property (nonatomic, assign) double barometerWeight;
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
        [self setupAltimeter];
        _hasListeners = NO;
        _isNewLocationAvailable = NO;
        _hasStartGpsAltitude = NO;  // 🆕
        _gpsWeight = 0.3;  // 🆕 GPS 30%
        _barometerWeight = 0.7;  // 🆕 기압계 70%
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
    
    // 🎯 최고 정밀도 설정 (안드로이드와 동일)
    self.distanceFilter = kCLDistanceFilterNone;  // 모든 이동 감지
    self.desiredAccuracy = kCLLocationAccuracyBest;  // 최고 정확도
    self.locationManager.distanceFilter = self.distanceFilter;
    self.locationManager.desiredAccuracy = self.desiredAccuracy;
    
    // 🚴 사이클링 최적화
    self.locationManager.activityType = CLActivityTypeFitness;  // 피트니스 활동
    
    RCTLogInfo(@"[RNRidableGpsTracker] ✅ Location manager configured with BEST accuracy for cycling");
}

- (void)setupAltimeter
{
    self.altimeter = [[CMAltimeter alloc] init];
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
    
    // 🆕 exerciseType 처리
    if (config[@"exerciseType"]) {
        NSString *exerciseType = config[@"exerciseType"];
        
        if ([exerciseType isEqualToString:@"bicycle"]) {
            // 자전거 설정
            self.locationManager.activityType = CLActivityTypeFitness;
            // 필요한 추가 설정
        } else if ([exerciseType isEqualToString:@"running"]) {
            // 러닝 설정
            self.locationManager.activityType = CLActivityTypeFitness;
        } else if ([exerciseType isEqualToString:@"hiking"]) {
            // 하이킹 설정
            self.locationManager.activityType = CLActivityTypeFitness;
        } else if ([exerciseType isEqualToString:@"walking"]) {
            // 걷기 설정
            self.locationManager.activityType = CLActivityTypeFitness;
        }
        
        // 기본값 처리 (없으면 bicycle)
        if (!exerciseType) {
            exerciseType = @"bicycle";
        }
    } else {
        // 기본값: bicycle
        self.locationManager.activityType = CLActivityTypeFitness;
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
    
    RCTLogInfo(@"[RNRidableGpsTracker] Starting GPS tracking with BEST accuracy, hasListeners: %d", self.hasListeners);
    
    // 짧은 대기 시간 후 시작 (JS 리스너 등록 완료 보장)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.isTracking = YES;
        [self.locationManager startUpdatingLocation];
        [self startAltimeterUpdates];
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
    [self stopAltimeterUpdates];
    [self stopRepeatLocationUpdates];
    RCTLogInfo(@"[RNRidableGpsTracker] GPS tracking stopped");
    resolve(nil);
}

RCT_EXPORT_METHOD(getCurrentLocation:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    if (self.lastLocation) {
        resolve([self convertLocationToDict:self.lastLocation withNewFlag:NO]);
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
        @"authorizationStatus": status,
        @"isBarometerAvailable": @([CMAltimeter isRelativeAltitudeAvailable])
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

#pragma mark - Barometer (Altimeter)

- (void)startAltimeterUpdates
{
    if (![CMAltimeter isRelativeAltitudeAvailable]) {
        RCTLogWarn(@"[RNRidableGpsTracker] ⚠️ Barometer not available on this device");
        return;
    }
    
    RCTLogInfo(@"[RNRidableGpsTracker] Starting barometer updates with Kalman filter");
    
    // 🆕 시작 시 기준점 리셋
    self.hasStartGpsAltitude = NO;
    
    [self.altimeter startRelativeAltitudeUpdatesToQueue:[NSOperationQueue mainQueue]
                                            withHandler:^(CMAltitudeData *altitudeData, NSError *error) {
        if (error) {
            RCTLogError(@"[RNRidableGpsTracker] Altimeter error: %@", error.localizedDescription);
            return;
        }
        
        if (altitudeData) {
            self.lastAltitudeData = altitudeData;
            
            // 🆕 칼만 필터 융합 (GPS와 기압계 데이터 결합)
            if (self.lastLocation && self.hasStartGpsAltitude && self.lastLocation.verticalAccuracy >= 0) {
                double gpsAltitude = self.lastLocation.altitude;
                double relativeAltitude = [altitudeData.relativeAltitude doubleValue];
                
                // 기압계 기반 절대 고도 = 시작 GPS 고도 + 상대 변화량
                double barometerAltitude = self.startGpsAltitude + relativeAltitude;
                
                // 🎯 칼만 필터: GPS(30%) + 기압계(70%) 가중 평균
                self.enhancedAltitude = (gpsAltitude * self.gpsWeight) + (barometerAltitude * self.barometerWeight);
                
                RCTLogInfo(@"[RNRidableGpsTracker] 📊 Altitude fusion: GPS=%.1fm, Baro=%.1fm, Enhanced=%.1fm",
                          gpsAltitude, barometerAltitude, self.enhancedAltitude);
            }
            
            RCTLogInfo(@"[RNRidableGpsTracker] Barometer update: relativeAltitude=%.2fm, pressure=%.2fkPa",
                       [altitudeData.relativeAltitude doubleValue],
                       [altitudeData.pressure doubleValue]);
        }
    }];
}

- (void)stopAltimeterUpdates
{
    [self.altimeter stopRelativeAltitudeUpdates];
    self.lastAltitudeData = nil;
    self.hasStartGpsAltitude = NO;  // 🆕 리셋
    self.enhancedAltitude = 0.0;  // 🆕 리셋
    RCTLogInfo(@"[RNRidableGpsTracker] Stopped barometer updates");
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    CLLocation *location = locations.lastObject;
    if (!location) return;
    
    // 🆕 첫 GPS 고도를 기준점으로 설정 (수직 정확도가 유효할 때만)
    if (!self.hasStartGpsAltitude && location.verticalAccuracy >= 0) {
        self.startGpsAltitude = location.altitude;
        self.enhancedAltitude = self.startGpsAltitude;
        self.hasStartGpsAltitude = YES;
        RCTLogInfo(@"[RNRidableGpsTracker] 🎯 Start GPS altitude set: %.1fm (accuracy: %.1fm)", 
                   self.startGpsAltitude, location.verticalAccuracy);
    }
    
    self.lastLocation = location;
    self.lastLocationTimestamp = location.timestamp;
    self.isNewLocationAvailable = YES;  // 새로운 위치 수신
    
    RCTLogInfo(@"[RNRidableGpsTracker] 🆕 NEW Location update: lat=%.6f, lng=%.6f, alt=%.1fm, accuracy=%.1fm, tracking=%d, hasListeners=%d",
               location.coordinate.latitude, location.coordinate.longitude, location.altitude, 
               location.horizontalAccuracy, self.isTracking, self.hasListeners);
    
    if (self.isTracking && self.hasListeners) {
        [self sendEventWithName:@"location" body:[self convertLocationToDict:location withNewFlag:YES]];
        self.isNewLocationAvailable = NO;  // 전송 후 플래그 리셋
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
        // isNewLocationAvailable이 YES이면 새 데이터, NO이면 반복 데이터
        BOOL isNew = self.isNewLocationAvailable;
        [self sendEventWithName:@"location" body:[self convertLocationToDict:self.lastLocation withNewFlag:isNew]];
        
        if (isNew) {
            self.isNewLocationAvailable = NO;  // 전송 후 플래그 리셋
            RCTLogInfo(@"[RNRidableGpsTracker] 🆕 Sent NEW location data");
        }
    } else if (self.lastLocation && self.isTracking && !self.hasListeners) {
        RCTLogWarn(@"[RNRidableGpsTracker] ⚠️ Repeat location update skipped - no listeners registered");
    }
}

#pragma mark - Helper

- (NSDictionary *)convertLocationToDict:(CLLocation *)location withNewFlag:(BOOL)isNew
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:@{
        @"latitude": @(location.coordinate.latitude),
        @"longitude": @(location.coordinate.longitude),
        @"altitude": @(location.altitude),  // GPS 기반 고도
        @"accuracy": @(location.horizontalAccuracy),
        @"speed": @(location.speed >= 0 ? location.speed : 0),
        @"bearing": @(location.course >= 0 ? location.course : 0),
        @"timestamp": @([location.timestamp timeIntervalSince1970] * 1000),
        @"isNewLocation": @(isNew)  // 🆕 새 위치 데이터 여부
    }];
    
    // 🆕 기압계 데이터가 있으면 enhancedAltitude 추가
    if (self.lastAltitudeData && self.hasStartGpsAltitude) {
        double relativeAltitude = [self.lastAltitudeData.relativeAltitude doubleValue];
        double pressure = [self.lastAltitudeData.pressure doubleValue];
        
        // 🎯 칼만 필터로 융합된 고도 사용
        dict[@"enhancedAltitude"] = @(self.enhancedAltitude);
        dict[@"relativeAltitude"] = @(relativeAltitude);  // 시작점 대비 상대 고도
        dict[@"pressure"] = @(pressure);  // 기압 (kPa)
        
        if (isNew) {
            RCTLogInfo(@"[RNRidableGpsTracker] Enhanced altitude: GPS=%.2fm, relative=%.2fm, enhanced=%.2fm, pressure=%.2fkPa",
                       location.altitude, relativeAltitude, self.enhancedAltitude, pressure);
        }
    }
    
    return dict;
}

@end