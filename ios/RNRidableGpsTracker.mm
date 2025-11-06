#import "RNRidableGpsTracker.h"
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <React/RCTLog.h>

@interface RNRidableGpsTracker () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, strong) CMAltimeter *altimeter;
@property (nonatomic, strong) CMMotionManager *motionManager;
@property (nonatomic, strong) CLLocation *lastLocation;
@property (nonatomic, strong) CMAltitudeData *lastAltitudeData;
@property (nonatomic, assign) BOOL isTracking;
@property (nonatomic, assign) CLLocationDistance distanceFilter;
@property (nonatomic, assign) CLLocationAccuracy desiredAccuracy;
@property (nonatomic, assign) BOOL hasListeners;
@property (nonatomic, strong) NSTimer *repeatLocationTimer;
@property (nonatomic, strong) NSDate *lastLocationTimestamp;
@property (nonatomic, assign) BOOL isNewLocationAvailable;

// 고도 보정
@property (nonatomic, assign) double startGpsAltitude;
@property (nonatomic, assign) BOOL hasStartGpsAltitude;
@property (nonatomic, assign) double enhancedAltitude;

// Kalman 필터
@property (nonatomic, assign) double kalmanLat;
@property (nonatomic, assign) double kalmanLng;
@property (nonatomic, assign) double variance;
@property (nonatomic, assign) BOOL isKalmanInitialized;
@property (nonatomic, assign) double processNoise;
@property (nonatomic, assign) BOOL useKalmanFilter;

// 설정
@property (nonatomic, strong) NSString *exerciseType;
@property (nonatomic, assign) BOOL advancedTracking;

// 가속계 데이터
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *accelerometerBuffer;
@property (nonatomic, assign) double lastAccelX;
@property (nonatomic, assign) double lastAccelY;
@property (nonatomic, assign) double lastAccelZ;
@property (nonatomic, assign) NSTimeInterval lastAccelTimestamp;

// 자이로스코프 데이터
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *gyroscopeBuffer;
@property (nonatomic, assign) double lastGyroX;
@property (nonatomic, assign) double lastGyroY;
@property (nonatomic, assign) double lastGyroZ;
@property (nonatomic, assign) NSTimeInterval lastGyroTimestamp;

@property (nonatomic, assign) NSInteger maxBufferSize;

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
        [self setupMotionManager];
        _hasListeners = NO;
        _isNewLocationAvailable = NO;
        _hasStartGpsAltitude = NO;
        _isKalmanInitialized = NO;
        _useKalmanFilter = NO;
        _exerciseType = @"bicycle";
        _advancedTracking = NO;
        _variance = 0.0;
        _processNoise = 0.0;
        _maxBufferSize = 10;
        _accelerometerBuffer = [NSMutableArray arrayWithCapacity:_maxBufferSize];
        _gyroscopeBuffer = [NSMutableArray arrayWithCapacity:_maxBufferSize];
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
    self.distanceFilter = kCLDistanceFilterNone;
    self.desiredAccuracy = kCLLocationAccuracyBest;
    self.locationManager.distanceFilter = self.distanceFilter;
    self.locationManager.desiredAccuracy = self.desiredAccuracy;
    self.locationManager.activityType = CLActivityTypeFitness;
    
    RCTLogInfo(@"[RNRidableGpsTracker] ✅ Location manager configured");
}

- (void)setupAltimeter
{
    self.altimeter = [[CMAltimeter alloc] init];
}

- (void)setupMotionManager
{
    self.motionManager = [[CMMotionManager alloc] init];
    self.motionManager.accelerometerUpdateInterval = 0.02; // 50Hz
    self.motionManager.gyroUpdateInterval = 0.02;
    
    if (self.motionManager.isAccelerometerAvailable) {
        RCTLogInfo(@"[RNRidableGpsTracker] ✅ Accelerometer available");
    }
    
    if (self.motionManager.isGyroAvailable) {
        RCTLogInfo(@"[RNRidableGpsTracker] ✅ Gyroscope available");
    }
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"location", @"error", @"authorizationChanged"];
}

- (void)startObserving
{
    self.hasListeners = YES;
    RCTLogInfo(@"[RNRidableGpsTracker] ✅ startObserving");
}

- (void)stopObserving
{
    self.hasListeners = NO;
    RCTLogInfo(@"[RNRidableGpsTracker] stopObserving");
}

#pragma mark - Kalman Filter

- (void)initKalmanFilter:(CLLocation *)location
{
    self.kalmanLat = location.coordinate.latitude;
    self.kalmanLng = location.coordinate.longitude;
    self.variance = location.horizontalAccuracy * location.horizontalAccuracy;
    self.isKalmanInitialized = YES;
    
    RCTLogInfo(@"[KalmanFilter] Initialized: lat=%.6f, lng=%.6f, variance=%.2f",
               self.kalmanLat, self.kalmanLng, self.variance);
}

- (CLLocation *)applyKalmanFilter:(CLLocation *)newLocation
{
    if (!self.isKalmanInitialized) {
        [self initKalmanFilter:newLocation];
        return newLocation;
    }
    
    double measurementNoise = newLocation.horizontalAccuracy * newLocation.horizontalAccuracy;
    double predictedVariance = self.variance + self.processNoise;
    double kalmanGain = predictedVariance / (predictedVariance + measurementNoise);
    
    self.kalmanLat = self.kalmanLat + kalmanGain * (newLocation.coordinate.latitude - self.kalmanLat);
    self.kalmanLng = self.kalmanLng + kalmanGain * (newLocation.coordinate.longitude - self.kalmanLng);
    self.variance = (1.0 - kalmanGain) * predictedVariance;
    
    CLLocationCoordinate2D filteredCoordinate = CLLocationCoordinate2DMake(self.kalmanLat, self.kalmanLng);
    CLLocation *filteredLocation = [[CLLocation alloc] initWithCoordinate:filteredCoordinate
                                                                 altitude:newLocation.altitude
                                                       horizontalAccuracy:sqrt(self.variance)
                                                         verticalAccuracy:newLocation.verticalAccuracy
                                                                   course:newLocation.course
                                                                    speed:newLocation.speed
                                                                timestamp:newLocation.timestamp];
    
    return filteredLocation;
}

- (void)resetKalmanFilter
{
    self.isKalmanInitialized = NO;
    self.variance = 0.0;
    RCTLogInfo(@"[KalmanFilter] Reset");
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
    
    if (config[@"advancedTracking"]) {
        self.advancedTracking = [config[@"advancedTracking"] boolValue];
    } else {
        self.advancedTracking = NO;
    }
    
    if (config[@"exerciseType"]) {
        NSString *exerciseType = config[@"exerciseType"];
        self.exerciseType = exerciseType;
        
        if ([exerciseType isEqualToString:@"bicycle"]) {
            self.locationManager.activityType = CLActivityTypeFitness;
            self.useKalmanFilter = NO;
            self.processNoise = 0.0;
            RCTLogInfo(@"[Config] 🚴 Bicycle: Kalman OFF, Advanced=%d", self.advancedTracking);
            
        } else if ([exerciseType isEqualToString:@"running"]) {
            self.locationManager.activityType = CLActivityTypeFitness;
            self.useKalmanFilter = YES;
            self.processNoise = 0.5;
            RCTLogInfo(@"[Config] 🏃 Running: Kalman ON (light), Advanced=%d", self.advancedTracking);
            
        } else if ([exerciseType isEqualToString:@"hiking"]) {
            self.locationManager.activityType = CLActivityTypeFitness;
            self.useKalmanFilter = YES;
            self.processNoise = 1.0;
            RCTLogInfo(@"[Config] 🥾 Hiking: Kalman ON (medium), Advanced=%d", self.advancedTracking);
            
        } else if ([exerciseType isEqualToString:@"walking"]) {
            self.locationManager.activityType = CLActivityTypeFitness;
            self.useKalmanFilter = YES;
            self.processNoise = 2.0;
            RCTLogInfo(@"[Config] 🚶 Walking: Kalman ON (strong), Advanced=%d", self.advancedTracking);
        }
    } else {
        self.exerciseType = @"bicycle";
        self.locationManager.activityType = CLActivityTypeFitness;
        self.useKalmanFilter = NO;
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
    
    RCTLogInfo(@"[RNRidableGpsTracker] 🚀 Starting: %@ (Advanced: %d)", self.exerciseType, self.advancedTracking);
    
    [self resetKalmanFilter];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.isTracking = YES;
        [self.locationManager startUpdatingLocation];
        [self startAltimeterUpdates];
        
        if (self.advancedTracking) {
            [self startAdvancedSensors];
        }
        
        [self startRepeatLocationUpdates];
        RCTLogInfo(@"[RNRidableGpsTracker] ✅ Tracking started");
        resolve(nil);
    });
}

RCT_EXPORT_METHOD(stop:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    self.isTracking = NO;
    [self.locationManager stopUpdatingLocation];
    [self stopAltimeterUpdates];
    [self stopAdvancedSensors];
    [self stopRepeatLocationUpdates];
    [self resetKalmanFilter];
    
    RCTLogInfo(@"[RNRidableGpsTracker] 🛑 Tracking stopped");
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
        @"isBarometerAvailable": @([CMAltimeter isRelativeAltitudeAvailable]),
        @"isAccelerometerAvailable": @(self.motionManager.isAccelerometerAvailable),
        @"isGyroscopeAvailable": @(self.motionManager.isGyroAvailable),
        @"exerciseType": self.exerciseType,
        @"advancedTracking": @(self.advancedTracking),
        @"useKalmanFilter": @(self.useKalmanFilter)
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
        RCTLogWarn(@"[RNRidableGpsTracker] ⚠️ Barometer not available");
        return;
    }
    
    self.hasStartGpsAltitude = NO;
    
    [self.altimeter startRelativeAltitudeUpdatesToQueue:[NSOperationQueue mainQueue]
                                            withHandler:^(CMAltitudeData *altitudeData, NSError *error) {
        if (error) {
            RCTLogError(@"[Altimeter] Error: %@", error.localizedDescription);
            return;
        }
        
        if (altitudeData) {
            self.lastAltitudeData = altitudeData;
            
            if (self.lastLocation && self.hasStartGpsAltitude && self.lastLocation.verticalAccuracy >= 0) {
                double gpsAltitude = self.lastLocation.altitude;
                double relativeAltitude = [altitudeData.relativeAltitude doubleValue];
                double barometerAltitude = self.startGpsAltitude + relativeAltitude;
                self.enhancedAltitude = (gpsAltitude * 0.3) + (barometerAltitude * 0.7);
            }
        }
    }];
    
    RCTLogInfo(@"[RNRidableGpsTracker] 📊 Barometer started");
}

- (void)stopAltimeterUpdates
{
    [self.altimeter stopRelativeAltitudeUpdates];
    self.lastAltitudeData = nil;
    self.hasStartGpsAltitude = NO;
    self.enhancedAltitude = 0.0;
    RCTLogInfo(@"[RNRidableGpsTracker] Barometer stopped");
}

#pragma mark - Advanced Sensors

- (void)startAdvancedSensors
{
    if (!self.advancedTracking) return;
    
    if (self.motionManager.isAccelerometerAvailable) {
        [self.accelerometerBuffer removeAllObjects];
        
        [self.motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue]
                                                  withHandler:^(CMAccelerometerData *data, NSError *error) {
            if (error) {
                RCTLogError(@"[Accelerometer] Error: %@", error.localizedDescription);
                return;
            }
            
            if (data) {
                self.lastAccelX = data.acceleration.x * 9.81;
                self.lastAccelY = data.acceleration.y * 9.81;
                self.lastAccelZ = data.acceleration.z * 9.81;
                self.lastAccelTimestamp = [[NSDate date] timeIntervalSince1970];
                
                NSDictionary *reading = @{
                    @"x": @(self.lastAccelX),
                    @"y": @(self.lastAccelY),
                    @"z": @(self.lastAccelZ),
                    @"timestamp": @(self.lastAccelTimestamp)
                };
                
                [self.accelerometerBuffer addObject:reading];
                
                if (self.accelerometerBuffer.count > self.maxBufferSize) {
                    [self.accelerometerBuffer removeObjectAtIndex:0];
                }
            }
        }];
        
        RCTLogInfo(@"[RNRidableGpsTracker] 📊 Accelerometer started");
    }
    
    if (self.motionManager.isGyroAvailable) {
        [self.gyroscopeBuffer removeAllObjects];
        
        [self.motionManager startGyroUpdatesToQueue:[NSOperationQueue mainQueue]
                                        withHandler:^(CMGyroData *data, NSError *error) {
            if (error) {
                RCTLogError(@"[Gyroscope] Error: %@", error.localizedDescription);
                return;
            }
            
            if (data) {
                self.lastGyroX = data.rotationRate.x;
                self.lastGyroY = data.rotationRate.y;
                self.lastGyroZ = data.rotationRate.z;
                self.lastGyroTimestamp = [[NSDate date] timeIntervalSince1970];
                
                NSDictionary *reading = @{
                    @"x": @(self.lastGyroX),
                    @"y": @(self.lastGyroY),
                    @"z": @(self.lastGyroZ),
                    @"timestamp": @(self.lastGyroTimestamp)
                };
                
                [self.gyroscopeBuffer addObject:reading];
                
                if (self.gyroscopeBuffer.count > self.maxBufferSize) {
                    [self.gyroscopeBuffer removeObjectAtIndex:0];
                }
            }
        }];
        
        RCTLogInfo(@"[RNRidableGpsTracker] 📊 Gyroscope started");
    }
}

- (void)stopAdvancedSensors
{
    if (self.motionManager.isAccelerometerActive) {
        [self.motionManager stopAccelerometerUpdates];
        [self.accelerometerBuffer removeAllObjects];
        RCTLogInfo(@"[RNRidableGpsTracker] Accelerometer stopped");
    }
    
    if (self.motionManager.isGyroActive) {
        [self.motionManager stopGyroUpdates];
        [self.gyroscopeBuffer removeAllObjects];
        RCTLogInfo(@"[RNRidableGpsTracker] Gyroscope stopped");
    }
}

#pragma mark - Motion Analysis

- (NSDictionary *)generateMotionAnalysis
{
    if (!self.advancedTracking || self.accelerometerBuffer.count == 0) {
        return nil;
    }
    
    // 1. 진동 강도 계산
    double vibrationIntensity = [self calculateVibrationIntensity];
    NSString *roadSurfaceQuality;
    
    if (vibrationIntensity < 0.2) {
        roadSurfaceQuality = @"smooth";
    } else if (vibrationIntensity < 0.5) {
        roadSurfaceQuality = @"rough";
    } else {
        roadSurfaceQuality = @"very_rough";
    }
    
    // 2. 코너링 강도
    double corneringIntensity = 0.0;
    if (self.gyroscopeBuffer.count > 0) {
        double totalRotZ = 0.0;
        for (NSDictionary *reading in self.gyroscopeBuffer) {
            totalRotZ += fabs([reading[@"z"] doubleValue]);
        }
        double avgRotationZ = totalRotZ / self.gyroscopeBuffer.count;
        corneringIntensity = MIN(avgRotationZ / 3.0, 1.0);
    }
    
    // 3. 경사도 분석
    NSDictionary *inclineData = [self calculateIncline];
    
    // 4. 수직 가속도 (iOS 좌표계 고려)
    double verticalAcceleration = fabs(self.lastAccelZ) - 9.81;
    
    return @{
        @"roadSurfaceQuality": roadSurfaceQuality,
        @"vibrationIntensity": @(vibrationIntensity),
        @"corneringIntensity": @(corneringIntensity),
        @"inclineAngle": inclineData[@"angle"],
        @"isClimbing": inclineData[@"isClimbing"],
        @"isDescending": inclineData[@"isDescending"],
        @"verticalAcceleration": @(verticalAcceleration)
    };
}

- (double)calculateVibrationIntensity
{
    if (self.accelerometerBuffer.count < 2) return 0.0;
    
    double totalVariation = 0.0;
    
    for (NSInteger i = 1; i < self.accelerometerBuffer.count; i++) {
        NSDictionary *prev = self.accelerometerBuffer[i - 1];
        NSDictionary *curr = self.accelerometerBuffer[i];
        
        double dx = [curr[@"x"] doubleValue] - [prev[@"x"] doubleValue];
        double dy = [curr[@"y"] doubleValue] - [prev[@"y"] doubleValue];
        double dz = [curr[@"z"] doubleValue] - [prev[@"z"] doubleValue];
        
        totalVariation += sqrt(dx * dx + dy * dy + dz * dz);
    }
    
    double avgVariation = totalVariation / (self.accelerometerBuffer.count - 1);
    
    return MAX(0.0, MIN(1.0, (avgVariation - 0.5) / 2.5));
}

- (NSDictionary *)calculateIncline
{
    if (self.accelerometerBuffer.count == 0) {
        return @{
            @"angle": @0.0,
            @"isClimbing": @NO,
            @"isDescending": @NO
        };
    }
    
    // 평균 계산
    double sumX = 0, sumY = 0, sumZ = 0;
    for (NSDictionary *reading in self.accelerometerBuffer) {
        sumX += [reading[@"x"] doubleValue];
        sumY += [reading[@"y"] doubleValue];
        sumZ += [reading[@"z"] doubleValue];
    }
    
    double avgX = sumX / self.accelerometerBuffer.count;
    double avgY = sumY / self.accelerometerBuffer.count;
    double avgZ = sumZ / self.accelerometerBuffer.count;
    
    // 🔧 경사각 계산 수정
    // iOS 좌표계: 기기를 수평으로 놓았을 때 Z ≈ -9.81 (아래 방향)
    // pitch angle (앞뒤 기울기) 계산
    double pitchAngle = atan2(avgY, sqrt(avgX * avgX + avgZ * avgZ)) * 180.0 / M_PI;
    
    // 각도 범위 제한 (-90 ~ 90)
    pitchAngle = fmax(-90.0, fmin(90.0, pitchAngle));
    
    BOOL isClimbing = pitchAngle > 5.0;
    BOOL isDescending = pitchAngle < -5.0;
    
    return @{
        @"angle": @(pitchAngle),
        @"isClimbing": @(isClimbing),
        @"isDescending": @(isDescending)
    };
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations
{
    CLLocation *location = locations.lastObject;
    if (!location) return;
    
    CLLocation *processedLocation = location;
    if (self.useKalmanFilter) {
        processedLocation = [self applyKalmanFilter:location];
    }
    
    if (!self.hasStartGpsAltitude && processedLocation.verticalAccuracy >= 0) {
        self.startGpsAltitude = processedLocation.altitude;
        self.enhancedAltitude = self.startGpsAltitude;
        self.hasStartGpsAltitude = YES;
        RCTLogInfo(@"[RNRidableGpsTracker] 🎯 Start altitude: %.1fm", self.startGpsAltitude);
    }
    
    self.lastLocation = processedLocation;
    self.lastLocationTimestamp = processedLocation.timestamp;
    self.isNewLocationAvailable = YES;
    
    if (self.isTracking && self.hasListeners) {
        [self sendEventWithName:@"location" body:[self convertLocationToDict:processedLocation withNewFlag:YES]];
        self.isNewLocationAvailable = NO;
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    RCTLogError(@"[RNRidableGpsTracker] Location error: %@", error.localizedDescription);
    
    if (self.hasListeners) {
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
    
    RCTLogInfo(@"[RNRidableGpsTracker] Authorization changed: %d", (int)status);
    
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
        
        [self sendEventWithName:@"authorizationChanged" body:@{@"status": statusString}];
    }
}

#pragma mark - Repeat Location Updates

- (void)startRepeatLocationUpdates
{
    [self stopRepeatLocationUpdates];
    
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
        });
    }
}

- (void)repeatLocationUpdate:(NSTimer *)timer
{
    if (self.lastLocation && self.isTracking && self.hasListeners) {
        BOOL isNew = self.isNewLocationAvailable;
        [self sendEventWithName:@"location" body:[self convertLocationToDict:self.lastLocation withNewFlag:isNew]];
        
        if (isNew) {
            self.isNewLocationAvailable = NO;
        }
    }
}

#pragma mark - Helper

- (NSDictionary *)convertLocationToDict:(CLLocation *)location withNewFlag:(BOOL)isNew
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:@{
        @"latitude": @(location.coordinate.latitude),
        @"longitude": @(location.coordinate.longitude),
        @"altitude": @(location.altitude),
        @"accuracy": @(location.horizontalAccuracy),
        @"speed": @(location.speed >= 0 ? location.speed : 0),
        @"bearing": @(location.course >= 0 ? location.course : 0),
        @"timestamp": @([location.timestamp timeIntervalSince1970] * 1000),
        @"isNewLocation": @(isNew),
        @"isKalmanFiltered": @(self.useKalmanFilter && self.isKalmanInitialized)
    }];
    
    // 기압계 데이터
    if (self.lastAltitudeData && self.hasStartGpsAltitude) {
        double relativeAltitude = [self.lastAltitudeData.relativeAltitude doubleValue];
        double pressure = [self.lastAltitudeData.pressure doubleValue];
        
        dict[@"enhancedAltitude"] = @(self.enhancedAltitude);
        dict[@"relativeAltitude"] = @(relativeAltitude);
        dict[@"pressure"] = @(pressure);
    }
    
    // 가속계 데이터
    if (self.advancedTracking && self.lastAccelTimestamp > 0) {
        double magnitude = sqrt(self.lastAccelX * self.lastAccelX + 
                               self.lastAccelY * self.lastAccelY + 
                               self.lastAccelZ * self.lastAccelZ);
        
        dict[@"accelerometer"] = @{
            @"x": @(self.lastAccelX),
            @"y": @(self.lastAccelY),
            @"z": @(self.lastAccelZ),
            @"magnitude": @(magnitude)
        };
    }
    
    // 자이로스코프 데이터
    if (self.advancedTracking && self.lastGyroTimestamp > 0) {
        double rotationRate = sqrt(self.lastGyroX * self.lastGyroX + 
                                   self.lastGyroY * self.lastGyroY + 
                                   self.lastGyroZ * self.lastGyroZ);
        
        dict[@"gyroscope"] = @{
            @"x": @(self.lastGyroX),
            @"y": @(self.lastGyroY),
            @"z": @(self.lastGyroZ),
            @"rotationRate": @(rotationRate)
        };
    }
    
    // 운동 분석 데이터
    if (self.advancedTracking) {
        NSDictionary *motionAnalysis = [self generateMotionAnalysis];
        if (motionAnalysis) {
            dict[@"motionAnalysis"] = motionAnalysis;
        }
    }
    
    return dict;
}

@end