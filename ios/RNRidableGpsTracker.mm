#import "RNRidableGpsTracker.h"
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
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

// Kalman 필터 (위치)
@property (nonatomic, assign) double kalmanLat;
@property (nonatomic, assign) double kalmanLng;
@property (nonatomic, assign) double variance;
@property (nonatomic, assign) BOOL isKalmanInitialized;
@property (nonatomic, assign) double processNoise;
@property (nonatomic, assign) BOOL useKalmanFilter;

// Kalman 필터 (고도)
@property (nonatomic, assign) double kalmanAltitude;
@property (nonatomic, assign) double altitudeVariance;
@property (nonatomic, assign) BOOL isAltitudeKalmanInitialized;
@property (nonatomic, assign) double altitudeProcessNoise;

// 설정
@property (nonatomic, strong) NSString *exerciseType;
@property (nonatomic, assign) BOOL useAccelerometer;
@property (nonatomic, assign) BOOL useGyroscope;
@property (nonatomic, assign) BOOL useMagnetometer;
@property (nonatomic, assign) BOOL useLight;
@property (nonatomic, assign) BOOL useNoise;

// 가속계 데이터 (Native 분석용)
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *accelerometerBuffer;
@property (nonatomic, assign) double lastAccelX;
@property (nonatomic, assign) double lastAccelY;
@property (nonatomic, assign) double lastAccelZ;
@property (nonatomic, assign) NSTimeInterval lastAccelTimestamp;

// 자이로스코프 데이터 (Native 분석용)
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *gyroscopeBuffer;
@property (nonatomic, assign) double lastGyroX;
@property (nonatomic, assign) double lastGyroY;
@property (nonatomic, assign) double lastGyroZ;
@property (nonatomic, assign) NSTimeInterval lastGyroTimestamp;

// 자기장 센서 데이터 (Native 분석용)
@property (nonatomic, assign) double lastMagX;
@property (nonatomic, assign) double lastMagY;
@property (nonatomic, assign) double lastMagZ;
@property (nonatomic, assign) double lastMagHeading;
@property (nonatomic, assign) NSTimeInterval lastMagTimestamp;

// 광센서 데이터
@property (nonatomic, assign) double currentLux;
@property (nonatomic, assign) NSTimeInterval lastLuxTimestamp;

// 소음 데이터
@property (nonatomic, assign) double currentDecibel;
@property (nonatomic, assign) NSTimeInterval lastDecibelTimestamp;
@property (nonatomic, strong) NSTimer *noiseTimer;

@property (nonatomic, assign) NSInteger maxBufferSize;

// 통계 데이터
@property (nonatomic, assign) double sessionDistance;
@property (nonatomic, assign) double sessionElevationGain;
@property (nonatomic, assign) double sessionElevationLoss;
@property (nonatomic, assign) double sessionMaxSpeed;
@property (nonatomic, assign) double sessionMovingTime;
@property (nonatomic, assign) double sessionElapsedTime;
@property (nonatomic, assign) NSTimeInterval sessionStartTime;
@property (nonatomic, strong) CLLocation *previousLocation;
@property (nonatomic, assign) double previousAltitude;
@property (nonatomic, assign) NSTimeInterval lastUpdateTime;

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
        _isAltitudeKalmanInitialized = NO;
        _useKalmanFilter = NO;
        _exerciseType = @"bicycle";
        _useAccelerometer = YES;
        _useGyroscope = YES;
        _useMagnetometer = NO;
        _useLight = YES;
        _useNoise = NO;
        _variance = 0.0;
        _processNoise = 0.0;
        _altitudeVariance = 0.0;
        _altitudeProcessNoise = 0.5;
        _maxBufferSize = 10;
        _accelerometerBuffer = [NSMutableArray arrayWithCapacity:_maxBufferSize];
        _gyroscopeBuffer = [NSMutableArray arrayWithCapacity:_maxBufferSize];
        
        _sessionDistance = 0.0;
        _sessionElevationGain = 0.0;
        _sessionElevationLoss = 0.0;
        _sessionMaxSpeed = 0.0;
        _sessionMovingTime = 0.0;
        _sessionElapsedTime = 0.0;
        _sessionStartTime = 0;
        _previousLocation = nil;
        _previousAltitude = 0.0;
        _lastUpdateTime = 0;
        
        // 광센서와 소음 초기화
        _currentLux = 0.0;
        _lastLuxTimestamp = 0;
        _currentDecibel = 0.0;
        _lastDecibelTimestamp = 0;
        _noiseTimer = nil;
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
    self.motionManager.accelerometerUpdateInterval = 0.02;  // 50 Hz
    self.motionManager.gyroUpdateInterval = 0.02;           // 50 Hz
    self.motionManager.magnetometerUpdateInterval = 1.0;    // 1 Hz
    
    if (self.motionManager.isAccelerometerAvailable) {
        RCTLogInfo(@"[RNRidableGpsTracker] ✅ Accelerometer available");
    }
    
    if (self.motionManager.isGyroAvailable) {
        RCTLogInfo(@"[RNRidableGpsTracker] ✅ Gyroscope available");
    }
    
    if (self.motionManager.isMagnetometerAvailable) {
        RCTLogInfo(@"[RNRidableGpsTracker] ✅ Magnetometer available");
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

#pragma mark - Kalman Filter (위치)

- (void)initKalmanFilter:(CLLocation *)location
{
    self.kalmanLat = location.coordinate.latitude;
    self.kalmanLng = location.coordinate.longitude;
    self.variance = location.horizontalAccuracy * location.horizontalAccuracy;
    self.isKalmanInitialized = YES;
    
    RCTLogInfo(@"[KalmanFilter] Position initialized");
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
    RCTLogInfo(@"[KalmanFilter] Position reset");
}

#pragma mark - Kalman Filter (고도)

- (void)initAltitudeKalmanFilter:(double)altitude
{
    self.kalmanAltitude = altitude;
    self.altitudeVariance = 25.0;
    self.isAltitudeKalmanInitialized = YES;
    
    RCTLogInfo(@"[KalmanFilter] Altitude initialized: %.2fm", altitude);
}

- (double)applyAltitudeKalmanFilter:(double)measuredAltitude accuracy:(double)accuracy
{
    if (!self.isAltitudeKalmanInitialized) {
        [self initAltitudeKalmanFilter:measuredAltitude];
        return measuredAltitude;
    }
    
    double measurementNoise = accuracy * accuracy;
    if (measurementNoise <= 0) {
        measurementNoise = 25.0;
    }
    
    double predictedVariance = self.altitudeVariance + self.altitudeProcessNoise;
    double kalmanGain = predictedVariance / (predictedVariance + measurementNoise);
    
    self.kalmanAltitude = self.kalmanAltitude + kalmanGain * (measuredAltitude - self.kalmanAltitude);
    self.altitudeVariance = (1.0 - kalmanGain) * predictedVariance;
    
    return self.kalmanAltitude;
}

- (void)resetAltitudeKalmanFilter
{
    self.isAltitudeKalmanInitialized = NO;
    self.altitudeVariance = 0.0;
    RCTLogInfo(@"[KalmanFilter] Altitude reset");
}

#pragma mark - 통계 계산

- (void)resetSessionStats
{
    self.sessionDistance = 0.0;
    self.sessionElevationGain = 0.0;
    self.sessionElevationLoss = 0.0;
    self.sessionMaxSpeed = 0.0;
    self.sessionMovingTime = 0.0;
    self.sessionElapsedTime = 0.0;
    self.sessionStartTime = [[NSDate date] timeIntervalSince1970];
    self.previousLocation = nil;
    self.previousAltitude = 0.0;
    self.lastUpdateTime = 0;
    
    RCTLogInfo(@"[Stats] Session reset");
}

- (void)updateSessionStats:(CLLocation *)location currentAltitude:(double)currentAltitude
{
    NSTimeInterval currentTime = [location.timestamp timeIntervalSince1970];
    
    if (!self.previousLocation) {
        self.previousLocation = location;
        self.previousAltitude = currentAltitude;
        self.lastUpdateTime = currentTime;
        return;
    }
    
    CLLocationDistance distance = [self.previousLocation distanceFromLocation:location];
    
    if (distance > 0.5 && distance < 100) {
        self.sessionDistance += distance;
    }
    
    NSTimeInterval timeDelta = currentTime - self.lastUpdateTime;
    if (timeDelta > 0 && timeDelta < 10) {
        self.sessionElapsedTime += timeDelta;
        
        if (location.speed >= 0.5) {
            self.sessionMovingTime += timeDelta;
        }
    }
    
    double elevationChange = currentAltitude - self.previousAltitude;
    
    if (fabs(elevationChange) > 0.5) {
        if (elevationChange > 0) {
            self.sessionElevationGain += elevationChange;
        } else {
            self.sessionElevationLoss += fabs(elevationChange);
        }
    }
    
    if (location.speed >= 0 && location.speed > self.sessionMaxSpeed) {
        self.sessionMaxSpeed = location.speed;
    }
    
    self.previousLocation = location;
    self.previousAltitude = currentAltitude;
    self.lastUpdateTime = currentTime;
}

- (double)calculateGrade:(CLLocation *)location currentAltitude:(double)currentAltitude
{
    if (!self.previousLocation) {
        return 0.0;
    }
    
    CLLocationDistance horizontalDistance = [self.previousLocation distanceFromLocation:location];
    
    if (horizontalDistance < 5.0) {
        return 0.0;
    }
    
    double elevationChange = currentAltitude - self.previousAltitude;
    double grade = (elevationChange / horizontalDistance) * 100.0;
    
    return fmax(-30.0, fmin(30.0, grade));
}

- (NSString *)getGradeCategory:(double)grade
{
    double absGrade = fabs(grade);
    
    if (absGrade < 2.0) return @"flat";
    if (absGrade < 5.0) return @"gentle";
    if (absGrade < 8.0) return @"moderate";
    if (absGrade < 12.0) return @"steep";
    return @"very_steep";
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
    
    // 센서 개별 제어
    if (config[@"useAccelerometer"]) {
        self.useAccelerometer = [config[@"useAccelerometer"] boolValue];
    } else {
        self.useAccelerometer = YES;
    }
    
    if (config[@"useGyroscope"]) {
        self.useGyroscope = [config[@"useGyroscope"] boolValue];
    } else {
        self.useGyroscope = YES;
    }
    
    if (config[@"useMagnetometer"]) {
        self.useMagnetometer = [config[@"useMagnetometer"] boolValue];
    } else {
        self.useMagnetometer = NO;
    }
    
    if (config[@"useLight"]) {
        self.useLight = [config[@"useLight"] boolValue];
    } else {
        self.useLight = YES;
    }
    
    if (config[@"useNoise"]) {
        self.useNoise = [config[@"useNoise"] boolValue];
    } else {
        self.useNoise = NO;
    }
    
    if (config[@"exerciseType"]) {
        NSString *exerciseType = config[@"exerciseType"];
        self.exerciseType = exerciseType;
        
        if ([exerciseType isEqualToString:@"bicycle"]) {
            self.locationManager.activityType = CLActivityTypeFitness;
            self.useKalmanFilter = NO;
            self.processNoise = 0.0;
            
        } else if ([exerciseType isEqualToString:@"running"]) {
            self.locationManager.activityType = CLActivityTypeFitness;
            self.useKalmanFilter = YES;
            self.processNoise = 0.5;
            
        } else if ([exerciseType isEqualToString:@"hiking"]) {
            self.locationManager.activityType = CLActivityTypeFitness;
            self.useKalmanFilter = YES;
            self.processNoise = 1.0;
            
        } else if ([exerciseType isEqualToString:@"walking"]) {
            self.locationManager.activityType = CLActivityTypeFitness;
            self.useKalmanFilter = YES;
            self.processNoise = 2.0;
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
    
    RCTLogInfo(@"[RNRidableGpsTracker] 🚀 Starting: %@", self.exerciseType);
    
    [self resetKalmanFilter];
    [self resetAltitudeKalmanFilter];
    [self resetSessionStats];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        self.isTracking = YES;
        [self.locationManager startUpdatingLocation];
        [self startAltimeterUpdates];
        
        // 센서별 시작
        [self startAdvancedSensors];
        
        // 광센서 시작 (useLight)
        if (self.useLight) {
            [self startLightSensor];
        }
        
        // 소음 측정 시작 (useNoise)
        if (self.useNoise) {
            [self startNoiseMeasurement];
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
    [self stopLightSensor];
    [self stopNoiseMeasurement];
    [self resetKalmanFilter];
    [self resetAltitudeKalmanFilter];
    
    RCTLogInfo(@"[RNRidableGpsTracker] 🛑 Tracking stopped");
    RCTLogInfo(@"[Stats] Final - Distance: %.2fm, Elevation Gain: %.2fm, Loss: %.2fm, Max Speed: %.2fm/s, Moving Time: %.0fs, Elapsed Time: %.0fs",
               self.sessionDistance, self.sessionElevationGain, self.sessionElevationLoss, self.sessionMaxSpeed, self.sessionMovingTime, self.sessionElapsedTime);
    
    resolve(nil);
}

RCT_EXPORT_METHOD(getCurrentLocation:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    if (self.lastLocation) {
        double currentAltitude;
        if ([CMAltimeter isRelativeAltitudeAvailable] && self.hasStartGpsAltitude) {
            currentAltitude = self.enhancedAltitude;
        } else {
            currentAltitude = self.kalmanAltitude;
        }
        resolve([self convertLocationToDict:self.lastLocation 
                                withNewFlag:NO 
                            currentAltitude:currentAltitude]);
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
        @"isMagnetometerAvailable": @(self.motionManager.isMagnetometerAvailable),
        @"exerciseType": self.exerciseType,
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
                
                double rawEnhancedAltitude = (gpsAltitude * 0.3) + (barometerAltitude * 0.7);
                
                self.enhancedAltitude = [self applyAltitudeKalmanFilter:rawEnhancedAltitude 
                                                               accuracy:self.lastLocation.verticalAccuracy];
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
    // 가속계 시작 (useAccelerometer)
    if (self.useAccelerometer && self.motionManager.isAccelerometerAvailable) {
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
        
        RCTLogInfo(@"[RNRidableGpsTracker] 📊 Accelerometer started (50 Hz)");
    }
    
    // 자이로스코프 시작 (useGyroscope)
    if (self.useGyroscope && self.motionManager.isGyroAvailable) {
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
        
        RCTLogInfo(@"[RNRidableGpsTracker] 📊 Gyroscope started (50 Hz)");
    }
    
    // 자기장 센서 시작 (useMagnetometer)
    if (self.useMagnetometer && self.motionManager.isMagnetometerAvailable) {
        [self.motionManager startMagnetometerUpdatesToQueue:[NSOperationQueue mainQueue]
                                                withHandler:^(CMMagnetometerData *data, NSError *error) {
            if (error) {
                RCTLogError(@"[Magnetometer] Error: %@", error.localizedDescription);
                return;
            }
            
            if (data) {
                self.lastMagX = data.magneticField.x;
                self.lastMagY = data.magneticField.y;
                self.lastMagZ = data.magneticField.z;
                self.lastMagTimestamp = [[NSDate date] timeIntervalSince1970];
                
                double heading = atan2(self.lastMagY, self.lastMagX) * (180.0 / M_PI);
                if (heading < 0) {
                    heading += 360.0;
                }
                self.lastMagHeading = heading;
            }
        }];
        
        RCTLogInfo(@"[RNRidableGpsTracker] 🧭 Magnetometer started (1 Hz)");
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
    
    if (self.motionManager.isMagnetometerActive) {
        [self.motionManager stopMagnetometerUpdates];
        self.lastMagTimestamp = 0;
        RCTLogInfo(@"[RNRidableGpsTracker] 🧭 Magnetometer stopped");
    }
}

#pragma mark - Motion Analysis

- (NSDictionary *)generateMotionAnalysis
{
    // 가속계나 자이로스코프 중 하나라도 사용하지 않으면 nil
    if (!self.useAccelerometer && !self.useGyroscope) {
        return nil;
    }
    
    // 가속계 사용 시 진동 데이터 계산
    double vibrationLevel = 0.0;
    double vibrationIntensity = 0.0;
    NSString *roadSurfaceQuality = @"smooth";
    double inclineAngle = 0.0;
    BOOL isClimbing = NO;
    BOOL isDescending = NO;
    double verticalAcceleration = 0.0;
    
    if (self.useAccelerometer && self.accelerometerBuffer.count > 0) {
        // 원본 진동 수치 계산
        vibrationLevel = [self calculateVibrationLevel];
        
        // 정규화된 진동 강도
        vibrationIntensity = [self calculateVibrationIntensity];
        
        // 노면 품질 분류
        if (vibrationIntensity < 0.2) {
            roadSurfaceQuality = @"smooth";
        } else if (vibrationIntensity < 0.5) {
            roadSurfaceQuality = @"rough";
        } else {
            roadSurfaceQuality = @"very_rough";
        }
        
        NSDictionary *inclineData = [self calculateIncline];
        inclineAngle = [inclineData[@"angle"] doubleValue];
        isClimbing = [inclineData[@"isClimbing"] boolValue];
        isDescending = [inclineData[@"isDescending"] boolValue];
        verticalAcceleration = fabs(self.lastAccelZ) - 9.81;
    }
    
    // 자이로스코프 사용 시 코너링 데이터 계산
    double corneringIntensity = 0.0;
    if (self.useGyroscope && self.gyroscopeBuffer.count > 0) {
        double totalRotZ = 0.0;
        for (NSDictionary *reading in self.gyroscopeBuffer) {
            totalRotZ += fabs([reading[@"z"] doubleValue]);
        }
        double avgRotationZ = totalRotZ / self.gyroscopeBuffer.count;
        corneringIntensity = MIN(avgRotationZ / 3.0, 1.0);
    }
    
    return @{
        @"roadSurfaceQuality": roadSurfaceQuality,
        @"vibrationLevel": @(vibrationLevel),
        @"vibrationIntensity": @(vibrationIntensity),
        @"corneringIntensity": @(corneringIntensity),
        @"inclineAngle": @(inclineAngle),
        @"isClimbing": @(isClimbing),
        @"isDescending": @(isDescending),
        @"verticalAcceleration": @(verticalAcceleration)
    };
}

- (double)calculateVibrationLevel
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
    
    // 원본 평균 변화량 반환 (m/s²)
    return totalVariation / (self.accelerometerBuffer.count - 1);
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
    
    double sumX = 0, sumY = 0, sumZ = 0;
    for (NSDictionary *reading in self.accelerometerBuffer) {
        sumX += [reading[@"x"] doubleValue];
        sumY += [reading[@"y"] doubleValue];
        sumZ += [reading[@"z"] doubleValue];
    }
    
    double avgX = sumX / self.accelerometerBuffer.count;
    double avgY = sumY / self.accelerometerBuffer.count;
    double avgZ = sumZ / self.accelerometerBuffer.count;
    
    double pitchAngle = atan2(avgY, sqrt(avgX * avgX + avgZ * avgZ)) * 180.0 / M_PI;
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
        
        [self initAltitudeKalmanFilter:self.startGpsAltitude];
        
        RCTLogInfo(@"[RNRidableGpsTracker] 🎯 Start altitude: %.1fm", self.startGpsAltitude);
    }
    
    double currentAltitude;
    if ([CMAltimeter isRelativeAltitudeAvailable] && self.hasStartGpsAltitude) {
        currentAltitude = self.enhancedAltitude;
    } else {
        currentAltitude = [self applyAltitudeKalmanFilter:processedLocation.altitude 
                                                 accuracy:processedLocation.verticalAccuracy];
    }
    
    [self updateSessionStats:processedLocation currentAltitude:currentAltitude];
    
    self.lastLocation = processedLocation;
    self.lastLocationTimestamp = processedLocation.timestamp;
    self.isNewLocationAvailable = YES;
    
    // didUpdateLocations에서는 이벤트만 전송하고 플래그는 리셋하지 않음
    // repeatLocationUpdate에서 플래그를 확인하고 리셋함
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error
{
    // kCLErrorLocationUnknown (0)은 일시적인 에러로 무시
    // 시뮬레이터에서 위치 변경 시 자주 발생하며, 곧 정상 위치가 들어옴
    if (error.domain == kCLErrorDomain && error.code == kCLErrorLocationUnknown) {
        RCTLogInfo(@"[RNRidableGpsTracker] ⚠️ Temporary location unavailable, waiting for next update...");
        return;
    }
    
    // 그 외 실제 에러만 로깅 및 이벤트 전송
    RCTLogError(@"[RNRidableGpsTracker] Location error: %@ (code: %ld)", error.localizedDescription, (long)error.code);
    
    if (self.hasListeners) {
        [self sendEventWithName:@"error" body:@{
            @"code": @(error.code),
            @"message": error.localizedDescription,
            @"domain": error.domain
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
        
        double currentAltitude;
        if ([CMAltimeter isRelativeAltitudeAvailable] && self.hasStartGpsAltitude) {
            currentAltitude = self.enhancedAltitude;
        } else {
            currentAltitude = self.kalmanAltitude;
        }
        
        [self sendEventWithName:@"location" body:[self convertLocationToDict:self.lastLocation 
                                                                withNewFlag:isNew 
                                                            currentAltitude:currentAltitude]];
        
        // 타이머에서 플래그를 확인하고 리셋
        if (isNew) {
            self.isNewLocationAvailable = NO;
        }
    }
}

#pragma mark - Helper

- (NSDictionary *)convertLocationToDict:(CLLocation *)location 
                           withNewFlag:(BOOL)isNew 
                       currentAltitude:(double)currentAltitude
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
        @"isKalmanFiltered": @(self.useKalmanFilter && self.isKalmanInitialized),
        
        // 통계 데이터
        @"sessionDistance": @(self.sessionDistance),
        @"sessionElevationGain": @(self.sessionElevationGain),
        @"sessionElevationLoss": @(self.sessionElevationLoss),
        @"sessionMovingTime": @(self.sessionMovingTime),
        @"sessionElapsedTime": @(self.sessionElapsedTime),
        @"sessionMaxSpeed": @(self.sessionMaxSpeed),
        @"sessionAvgSpeed": @(self.sessionElapsedTime > 0 ? self.sessionDistance / self.sessionElapsedTime : 0.0),
        @"sessionMovingAvgSpeed": @(self.sessionMovingTime > 0 ? self.sessionDistance / self.sessionMovingTime : 0.0),
        @"isMoving": @(location.speed >= 0.5)
    }];
    
    // 기압계 데이터
    if (self.lastAltitudeData && self.hasStartGpsAltitude) {
        double relativeAltitude = [self.lastAltitudeData.relativeAltitude doubleValue];
        double pressure = [self.lastAltitudeData.pressure doubleValue];
        
        dict[@"enhancedAltitude"] = @(currentAltitude);
        dict[@"relativeAltitude"] = @(relativeAltitude);
        dict[@"pressure"] = @(pressure);
        
        double grade = [self calculateGrade:location currentAltitude:currentAltitude];
        dict[@"grade"] = @(grade);
        dict[@"gradeCategory"] = [self getGradeCategory:grade];
    } else {
        double grade = [self calculateGrade:location currentAltitude:currentAltitude];
        dict[@"grade"] = @(grade);
        dict[@"gradeCategory"] = [self getGradeCategory:grade];
    }
    
    // 모션 분석 결과만 전송 (Raw 센서 데이터 제거됨)
    if (self.useAccelerometer || self.useGyroscope) {
        NSDictionary *motionAnalysis = [self generateMotionAnalysis];
        if (motionAnalysis) {
            dict[@"motionAnalysis"] = motionAnalysis;
        }
    }
    
    // 광센서 데이터
    if (self.useLight && self.lastLuxTimestamp > 0) {
        dict[@"light"] = @{
            @"lux": @(self.currentLux),
            @"condition": [self getLightCondition:self.currentLux],
            @"isLowLight": @(self.currentLux < 50)
        };
    }
    
    // 소음 데이터
    if (self.useNoise && self.lastDecibelTimestamp > 0 && self.currentDecibel > 0) {
        dict[@"noise"] = @{
            @"decibel": @(self.currentDecibel),
            @"noiseLevel": [self getNoiseLevel:self.currentDecibel]
        };
    }
    
    // 자기장 데이터
    if (self.useMagnetometer && self.lastMagTimestamp > 0) {
        double magneticFieldStrength = sqrt(self.lastMagX * self.lastMagX + 
                                           self.lastMagY * self.lastMagY + 
                                           self.lastMagZ * self.lastMagZ);
        
        dict[@"magnetometer"] = @{
            @"heading": @(self.lastMagHeading),
            @"magneticFieldStrength": @(magneticFieldStrength),
            @"x": @(self.lastMagX),
            @"y": @(self.lastMagY),
            @"z": @(self.lastMagZ)
        };
    }
    
    return dict;
}

#pragma mark - 광센서

- (void)startLightSensor
{
    // iOS에서는 UIScreen brightness를 사용 (간접 측정)
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(screenBrightnessDidChange:)
                                                     name:UIScreenBrightnessDidChangeNotification
                                                   object:nil];
        
        // 초기값 설정
        [self updateLightLevel];
        RCTLogInfo(@"💡 Light sensor started");
    });
}

- (void)stopLightSensor
{
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:UIScreenBrightnessDidChangeNotification
                                                  object:nil];
    self.currentLux = 0.0;
    self.lastLuxTimestamp = 0;
    RCTLogInfo(@"💡 Light sensor stopped");
}

- (void)screenBrightnessDidChange:(NSNotification *)notification
{
    [self updateLightLevel];
}

- (void)updateLightLevel
{
    // iOS는 직접 광센서 접근 불가, UIScreen brightness 기반 추정
    CGFloat brightness = [UIScreen mainScreen].brightness;
    
    // brightness (0.0~1.0)를 lux로 변환 (추정)
    // 0.0 = 어두움 (~10 lux)
    // 0.5 = 실내 (~200 lux)
    // 1.0 = 밝음 (~10000 lux)
    
    if (brightness < 0.2) {
        self.currentLux = 10.0 + (brightness / 0.2) * 40.0;  // 10~50 lux
    } else if (brightness < 0.5) {
        self.currentLux = 50.0 + ((brightness - 0.2) / 0.3) * 150.0;  // 50~200 lux
    } else if (brightness < 0.8) {
        self.currentLux = 200.0 + ((brightness - 0.5) / 0.3) * 800.0;  // 200~1000 lux
    } else {
        self.currentLux = 1000.0 + ((brightness - 0.8) / 0.2) * 9000.0;  // 1000~10000 lux
    }
    
    self.lastLuxTimestamp = [[NSDate date] timeIntervalSince1970];
}

- (NSString *)getLightCondition:(double)lux
{
    if (lux < 10) return @"dark";
    if (lux < 50) return @"dim";
    if (lux < 200) return @"indoor";
    if (lux < 1000) return @"overcast";
    if (lux < 10000) return @"daylight";
    return @"bright_sunlight";
}

#pragma mark - 소음 측정

- (void)startNoiseMeasurement
{
    if (self.noiseTimer) {
        [self.noiseTimer invalidate];
    }
    
    self.noiseTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                       target:self
                                                     selector:@selector(measureNoiseLevel)
                                                     userInfo:nil
                                                      repeats:YES];
    
    RCTLogInfo(@"🎤 Noise measurement started (1 Hz)");
}

- (void)stopNoiseMeasurement
{
    if (self.noiseTimer) {
        [self.noiseTimer invalidate];
        self.noiseTimer = nil;
    }
    
    self.currentDecibel = 0.0;
    self.lastDecibelTimestamp = 0;
    RCTLogInfo(@"🎤 Noise measurement stopped");
}

- (void)measureNoiseLevel
{
    // AVAudioRecorder를 사용한 소음 측정
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *error = nil;
    
    [audioSession setCategory:AVAudioSessionCategoryRecord error:&error];
    if (error) {
        RCTLogError(@"Audio session error: %@", error);
        return;
    }
    
    [audioSession setActive:YES error:&error];
    if (error) {
        RCTLogError(@"Audio session activate error: %@", error);
        return;
    }
    
    // 임시 녹음 설정
    NSDictionary *settings = @{
        AVFormatIDKey: @(kAudioFormatAppleLossless),
        AVSampleRateKey: @44100.0,
        AVNumberOfChannelsKey: @1,
        AVEncoderAudioQualityKey: @(AVAudioQualityMin)
    };
    
    NSURL *url = [NSURL fileURLWithPath:@"/dev/null"];
    AVAudioRecorder *recorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&error];
    
    if (error || !recorder) {
        RCTLogError(@"Audio recorder error: %@", error);
        return;
    }
    
    [recorder prepareToRecord];
    recorder.meteringEnabled = YES;
    [recorder record];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [recorder updateMeters];
        
        // averagePowerForChannel: -160 ~ 0 dB 범위
        float averagePower = [recorder averagePowerForChannel:0];
        
        // -160 ~ 0 범위를 0 ~ 120 dB로 변환
        float decibel = MAX(0, MIN(120, averagePower + 120));
        
        self.currentDecibel = decibel;
        self.lastDecibelTimestamp = [[NSDate date] timeIntervalSince1970];
        
        [recorder stop];
        [audioSession setActive:NO error:nil];
    });
}

- (NSString *)getNoiseLevel:(double)decibel
{
    if (decibel < 30) return @"very_quiet";
    if (decibel < 50) return @"quiet";
    if (decibel < 60) return @"moderate";
    if (decibel < 70) return @"noisy";
    if (decibel < 85) return @"very_noisy";
    return @"dangerously_loud";
}

@end
