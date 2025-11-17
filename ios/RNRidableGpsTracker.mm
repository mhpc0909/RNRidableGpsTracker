#import "RNRidableGpsTracker.h"
#import <CoreLocation/CoreLocation.h>
#import <CoreMotion/CoreMotion.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <React/RCTLog.h>
#import <math.h>

static const double kMovementSpeedThreshold = 0.5;          // m/s
static const double kMovementHysteresis = 0.2;              // m/s
static const double kMinimumMovementDistance = 0.5;         // m
static const double kMaximumMovementDistance = 100.0;       // m
static const double kMaxMovingTimeDelta = 10.0;             // s
static const double kGradeDistanceThreshold = 5.0;          // m
static const double kGradeDistancePerSpeed = 1.0;           // m per (m/s)
static const double kGradeMinSpeedThreshold = 1.5;          // m/s
static const double kGradeMaxDeltaSlow = 3.0;               // % (very slow)
static const double kGradeMaxDeltaMedium = 6.0;             // % (medium speed)
static const double kGradeMaxDeltaFast = 10.0;              // % (high speed)
static const NSUInteger kGradeWindowSize = 3;
static const NSUInteger kStationaryGradeResetThreshold = 2;

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

// getCurrentLocation 콜백
@property (nonatomic, copy) RCTPromiseResolveBlock locationRequestResolve;
@property (nonatomic, copy) RCTPromiseRejectBlock locationRequestReject;
@property (nonatomic, assign) BOOL wasTrackingBeforeRequest;

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
@property (nonatomic, strong) AVAudioRecorder *noiseRecorder;
@property (nonatomic, strong) AVAudioSession *audioSession;

@property (nonatomic, assign) NSInteger maxBufferSize;

// 통계 데이터
@property (nonatomic, assign) double sessionDistance;
@property (nonatomic, assign) double sessionElevationGain;
@property (nonatomic, assign) double sessionElevationLoss;
@property (nonatomic, assign) double sessionMaxSpeed;
@property (nonatomic, assign) double sessionMovingTime;
@property (nonatomic, assign) double sessionElapsedTime;
@property (nonatomic, assign) NSTimeInterval sessionStartTime;
@property (nonatomic, assign) NSTimeInterval lastElapsedUpdateTime;
@property (nonatomic, assign) NSTimeInterval lastMovingUpdateTime;
@property (nonatomic, strong) CLLocation *previousLocation;
@property (nonatomic, assign) double previousAltitude;
@property (nonatomic, assign) NSTimeInterval lastUpdateTime;
@property (nonatomic, assign) BOOL isCurrentlyMoving;
@property (nonatomic, assign) double currentFilteredSpeed;
@property (nonatomic, strong) CLLocation *gradeBaseLocation;
@property (nonatomic, assign) double gradeBaseAltitude;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *recentGrades;
@property (nonatomic, assign) double lastSmoothedGrade;
@property (nonatomic, assign) NSUInteger stationaryGradeCounter;
@property (nonatomic, assign) double lastRawLatitude;
@property (nonatomic, assign) double lastRawLongitude;
@property (nonatomic, assign) double lastRawAltitude;
@property (nonatomic, assign) BOOL hasLastRawLocation;

// Pause 관련 상태
@property (nonatomic, assign) BOOL isPaused;
@property (nonatomic, assign) NSTimeInterval pauseStartTime;
@property (nonatomic, assign) BOOL skipNextDistanceUpdate;  // Resume 후 첫 번째 거리 계산 건너뛰기

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
        _altitudeProcessNoise = 3.0;
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
        _lastElapsedUpdateTime = 0;
        _lastMovingUpdateTime = 0;
        _previousLocation = nil;
        _previousAltitude = 0.0;
        _lastUpdateTime = 0;
        _isCurrentlyMoving = NO;
        _currentFilteredSpeed = 0.0;
        _gradeBaseLocation = nil;
        _gradeBaseAltitude = 0.0;
        _recentGrades = [NSMutableArray arrayWithCapacity:kGradeWindowSize];
        _lastSmoothedGrade = 0.0;
        _stationaryGradeCounter = 0;
        
        // 광센서와 소음 초기화
        _currentLux = 0.0;
        _lastLuxTimestamp = 0;
        _currentDecibel = 0.0;
        _lastDecibelTimestamp = 0;
        _noiseTimer = nil;
        _lastRawLatitude = 0.0;
        _lastRawLongitude = 0.0;
        _lastRawAltitude = 0.0;
        _hasLastRawLocation = NO;
        
        // Pause 상태 초기화
        _isPaused = NO;
        _pauseStartTime = 0;
        _skipNextDistanceUpdate = NO;
        
        // getCurrentLocation 콜백 초기화
        _locationRequestResolve = nil;
        _locationRequestReject = nil;
        _wasTrackingBeforeRequest = NO;
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
    self.locationManager.activityType = CLActivityTypeOtherNavigation;
    
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
    self.lastElapsedUpdateTime = self.sessionStartTime;
    self.lastMovingUpdateTime = self.sessionStartTime;
    self.previousLocation = nil;
    self.previousAltitude = 0.0;
    self.lastUpdateTime = 0;
    self.isCurrentlyMoving = NO;
    self.currentFilteredSpeed = 0.0;
    [self resetGradeTrackingWithLocation:nil currentAltitude:0.0];
    self.stationaryGradeCounter = 0;
    self.hasLastRawLocation = NO;
    self.lastRawLatitude = 0.0;
    self.lastRawLongitude = 0.0;
    self.lastRawAltitude = 0.0;
    
    // Pause 상태 초기화
    self.isPaused = NO;
    self.pauseStartTime = 0;
    self.skipNextDistanceUpdate = NO;
    
    RCTLogInfo(@"[Stats] Session reset");
}

- (void)updateSessionStats:(CLLocation *)location currentAltitude:(double)currentAltitude
{
    // Pause 중이면 통계 업데이트 안 함 (위치 트래킹은 지속)
    if (self.isPaused) {
        return;
    }
    
    NSTimeInterval systemTime = [[NSDate date] timeIntervalSince1970];
    [self updateElapsedTimeWithTimestamp:systemTime];
    
    NSTimeInterval locationTime = [location.timestamp timeIntervalSince1970];
    
    if (!self.previousLocation) {
        self.previousLocation = location;
        self.previousAltitude = currentAltitude;
        self.lastUpdateTime = locationTime;
        self.lastMovingUpdateTime = systemTime;
        [self resetGradeTrackingWithLocation:location currentAltitude:currentAltitude];
        return;
    }
    
    // Resume 후 첫 번째 GPS 업데이트는 거리 계산 건너뛰기
    // (pause 시점 위치와 resume 후 위치 사이의 거리는 포함하지 않음)
    if (self.skipNextDistanceUpdate) {
        self.skipNextDistanceUpdate = NO;
        // previousLocation을 현재 위치로 업데이트 (거리 계산 없이)
        self.previousLocation = location;
        self.previousAltitude = currentAltitude;
        self.lastUpdateTime = locationTime;
        self.lastMovingUpdateTime = systemTime;
        // Grade 기준점도 현재 위치로 재설정
        [self resetGradeTrackingWithLocation:location currentAltitude:currentAltitude];
        RCTLogInfo(@"[Resume] Skipped first distance update after resume");
        return;
    }
    
    CLLocationDistance distance = [self.previousLocation distanceFromLocation:location];
    NSTimeInterval timeDelta = locationTime - self.lastUpdateTime;
    
    BOOL distanceWithinBounds = (distance >= kMinimumMovementDistance && distance <= kMaximumMovementDistance);
    double derivedSpeed = (distanceWithinBounds && timeDelta > 0) ? distance / timeDelta : 0.0;
    BOOL distanceSuggestsMovement = (distanceWithinBounds && derivedSpeed >= kMovementSpeedThreshold);
    BOOL speedSuggestsMovement = (location.speed >= 0 && location.speed >= kMovementSpeedThreshold && distanceWithinBounds);
    BOOL isMoving = distanceSuggestsMovement || speedSuggestsMovement;
    
    if (!isMoving && self.isCurrentlyMoving) {
        BOOL distanceWithinHysteresis = (distance >= kMinimumMovementDistance * 0.4 && distance <= kMaximumMovementDistance);
        BOOL hysteresisSatisfied = distanceWithinHysteresis &&
            ((location.speed >= 0 && location.speed >= (kMovementSpeedThreshold - kMovementHysteresis)) ||
             (derivedSpeed >= (kMovementSpeedThreshold - kMovementHysteresis)));
        if (hysteresisSatisfied) {
            isMoving = YES;
        }
    }
    
    if (distanceWithinBounds) {
        self.sessionDistance += distance;
    }
    
    if (timeDelta > 0 && timeDelta < 10) {
        if (isMoving) {
            NSTimeInterval movingDelta = systemTime - self.lastMovingUpdateTime;
            if (movingDelta > 0 && movingDelta < kMaxMovingTimeDelta) {
                self.sessionMovingTime += movingDelta;
            }
            self.lastMovingUpdateTime = systemTime;
        } else {
            self.lastMovingUpdateTime = systemTime;
        }
    }
    
    if (isMoving) {
        double candidateSpeed = fmax(location.speed >= 0 ? location.speed : 0.0, derivedSpeed);
        self.currentFilteredSpeed = candidateSpeed;
    } else {
        self.currentFilteredSpeed = 0.0;
    }
    self.isCurrentlyMoving = isMoving;
    
    double elevationChange = currentAltitude - self.previousAltitude;
    
    // ✅ 거리 조건 제거: 상승/하강은 실제 고도 변화를 반영해야 함
    // ✅ 임계값 0.5m: GPS 노이즈 필터링 (일반적인 권장값)
    // ⚠️ 주의: Kalman 필터로 부드러워진 고도는 변화가 0.5m 미만일 수 있음
    //    만약 누적 상승이 0이면 임계값을 0.3m로 낮추거나, rawEnhancedAltitude 사용 고려
    if (fabs(elevationChange) > 0.5) {
        if (elevationChange > 0) {
            self.sessionElevationGain += elevationChange;
            RCTLogInfo(@"[Elevation] Gain: +%.2fm (current: %.2f, previous: %.2f)", elevationChange, currentAltitude, self.previousAltitude);
        } else {
            self.sessionElevationLoss += fabs(elevationChange);
            RCTLogInfo(@"[Elevation] Loss: -%.2fm (current: %.2f, previous: %.2f)", fabs(elevationChange), currentAltitude, self.previousAltitude);
        }
    } else if (fabs(elevationChange) > 0.1) {
        // 디버깅: 0.1m~0.5m 사이의 변화가 있는지 확인
        RCTLogInfo(@"[Elevation] Small change ignored: %.2fm (threshold: 0.5m)", elevationChange);
    }
    
    if (self.currentFilteredSpeed > self.sessionMaxSpeed) {
        self.sessionMaxSpeed = self.currentFilteredSpeed;
    }
    
    self.previousLocation = location;
    self.previousAltitude = currentAltitude;
    self.lastUpdateTime = locationTime;
}

- (double)calculateGrade:(CLLocation *)location currentAltitude:(double)currentAltitude
{
    CLLocation *baseLocation = self.gradeBaseLocation;
    if (!baseLocation) {
        [self resetGradeTrackingWithLocation:location currentAltitude:currentAltitude];
        return self.lastSmoothedGrade;
    }
    
    CLLocationDistance horizontalDistance = [baseLocation distanceFromLocation:location];
    double speed = fmax(0.0, self.currentFilteredSpeed);
    double dynamicThreshold = fmax(kGradeDistanceThreshold, speed * kGradeDistancePerSpeed);
    
    if (horizontalDistance < dynamicThreshold) {
        return self.lastSmoothedGrade;
    }
    
    if (horizontalDistance > kMaximumMovementDistance) {
        [self resetGradeTrackingWithLocation:location currentAltitude:currentAltitude];
        return self.lastSmoothedGrade;
    }
    
    double elevationChange = currentAltitude - self.gradeBaseAltitude;
    double rawGrade = (elevationChange / horizontalDistance) * 100.0;
    double clampedGrade = fmax(-30.0, fmin(30.0, rawGrade));
    
    // 속도에 따라 허용하는 경사 변화량을 다르게 설정
    double delta = clampedGrade - self.lastSmoothedGrade;
    double maxDelta;
    if (speed < kGradeMinSpeedThreshold) {
        maxDelta = kGradeMaxDeltaSlow;
    } else if (speed < 5.0) {
        maxDelta = kGradeMaxDeltaMedium;
    } else {
        maxDelta = kGradeMaxDeltaFast;
    }
    
    double limitedDelta = fmax(-maxDelta, fmin(maxDelta, delta));
    clampedGrade = self.lastSmoothedGrade + limitedDelta;
    
    [self.recentGrades addObject:@(clampedGrade)];
    if (self.recentGrades.count > kGradeWindowSize) {
        [self.recentGrades removeObjectAtIndex:0];
    }
    
    double sum = 0.0;
    for (NSNumber *value in self.recentGrades) {
        sum += value.doubleValue;
    }
    if (self.recentGrades.count > 0) {
        self.lastSmoothedGrade = sum / (double)self.recentGrades.count;
    } else {
        self.lastSmoothedGrade = 0.0;
    }
    
    self.gradeBaseLocation = location;
    self.gradeBaseAltitude = currentAltitude;
    
    return self.lastSmoothedGrade;
}

- (double)resolveGradeForLocation:(CLLocation *)location
                 currentAltitude:(double)currentAltitude
          updateStationaryState:(BOOL)updateStationaryState
{
    BOOL shouldZero = [self handleStationaryGradeStateForLocation:location
                                                currentAltitude:currentAltitude
                                           updateStationaryState:updateStationaryState];
    if (shouldZero) {
        return 0.0;
    }
    return [self calculateGrade:location currentAltitude:currentAltitude];
}

- (BOOL)handleStationaryGradeStateForLocation:(CLLocation *)location
                             currentAltitude:(double)currentAltitude
                        updateStationaryState:(BOOL)updateStationaryState
{
    if (self.isCurrentlyMoving) {
        if (updateStationaryState) {
            self.stationaryGradeCounter = 0;
        }
        return NO;
    }
    
    if (updateStationaryState && self.stationaryGradeCounter < kStationaryGradeResetThreshold) {
        self.stationaryGradeCounter += 1;
    }
    
    BOOL shouldZero = self.stationaryGradeCounter >= kStationaryGradeResetThreshold;
    if (shouldZero) {
        [self resetGradeTrackingWithLocation:location currentAltitude:currentAltitude];
    }
    return shouldZero;
}

- (void)resetGradeTrackingWithLocation:(CLLocation *)location currentAltitude:(double)currentAltitude
{
    if (location) {
        self.gradeBaseLocation = location;
        self.gradeBaseAltitude = currentAltitude;
    } else {
        self.gradeBaseLocation = nil;
        self.gradeBaseAltitude = 0.0;
    }
    [self.recentGrades removeAllObjects];
    self.lastSmoothedGrade = 0.0;
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
            self.locationManager.activityType = CLActivityTypeOtherNavigation;
            self.useKalmanFilter = NO;
            self.processNoise = 0.0;
            
        } else if ([exerciseType isEqualToString:@"running"]) {
            self.locationManager.activityType = CLActivityTypeOtherNavigation;
            self.useKalmanFilter = YES;
            // ✅ 러닝에서 Kalman 필터 완화 (더 빠르게 커브에 반응하도록 노이즈 증가)
            self.processNoise = 7.0;
            
        } else if ([exerciseType isEqualToString:@"hiking"]) {
            self.locationManager.activityType = CLActivityTypeOtherNavigation;
            self.useKalmanFilter = YES;
            self.processNoise = 1.0;
            
        } else if ([exerciseType isEqualToString:@"walking"]) {
            self.locationManager.activityType = CLActivityTypeOtherNavigation;
            self.useKalmanFilter = YES;
            self.processNoise = 1.0;
        }
    } else {
        self.exerciseType = @"bicycle";
        self.locationManager.activityType = CLActivityTypeOtherNavigation;
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

RCT_EXPORT_METHOD(pause:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    if (!self.isTracking) {
        reject(@"NOT_TRACKING", @"Tracking not started", nil);
        return;
    }
    
    if (self.isPaused) {
        reject(@"ALREADY_PAUSED", @"Already paused", nil);
        return;
    }
    
    self.isPaused = YES;
    self.pauseStartTime = [[NSDate date] timeIntervalSince1970];
    
    RCTLogInfo(@"[RNRidableGpsTracker] ⏸️ Tracking paused");
    resolve(nil);
}

RCT_EXPORT_METHOD(resume:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    if (!self.isTracking) {
        reject(@"NOT_TRACKING", @"Tracking not started", nil);
        return;
    }
    
    if (!self.isPaused) {
        reject(@"NOT_PAUSED", @"Not paused", nil);
        return;
    }
    
    NSTimeInterval resumeTime = [[NSDate date] timeIntervalSince1970];
    
    // Resume 시점에 lastElapsedUpdateTime을 현재 시간으로 업데이트
    // 이렇게 하면 pause 기간이 자동으로 제외됨
    self.lastElapsedUpdateTime = resumeTime;
    
    // Resume 후 첫 번째 GPS 업데이트에서 거리 계산을 건너뛰도록 플래그 설정
    // (pause 시점 위치와 resume 후 위치 사이의 거리는 포함하지 않음)
    self.skipNextDistanceUpdate = YES;
    
    self.isPaused = NO;
    self.pauseStartTime = 0;
    
    RCTLogInfo(@"[RNRidableGpsTracker] ▶️ Tracking resumed");
    resolve(nil);
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
    [self resetGradeTrackingWithLocation:nil currentAltitude:0.0];
    self.stationaryGradeCounter = 0;
    self.hasLastRawLocation = NO;
    
    // Pause 상태 초기화
    self.isPaused = NO;
    self.pauseStartTime = 0;
    self.skipNextDistanceUpdate = NO;
    
    RCTLogInfo(@"[RNRidableGpsTracker] 🛑 Tracking stopped");
    RCTLogInfo(@"[Stats] Final - Distance: %.2fm, Elevation Gain: %.2fm, Loss: %.2fm, Max Speed: %.2fm/s, Moving Time: %.0fs, Elapsed Time: %.0fs",
               self.sessionDistance, self.sessionElevationGain, self.sessionElevationLoss, self.sessionMaxSpeed, self.sessionMovingTime, self.sessionElapsedTime);
    
    resolve(nil);
}

RCT_EXPORT_METHOD(getCurrentLocation:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    // 권한 확인
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
    
    if (authStatus == kCLAuthorizationStatusNotDetermined) {
        reject(@"PERMISSION_NOT_DETERMINED", @"Location permission not determined", nil);
        return;
    }
    
    // 이미 요청이 진행 중인지 확인
    @synchronized(self) {
        if (self.locationRequestResolve) {
            reject(@"REQUEST_IN_PROGRESS", @"Location request already in progress", nil);
            return;
        }
        
        // 콜백 저장
        self.locationRequestResolve = resolve;
        self.locationRequestReject = reject;
        self.wasTrackingBeforeRequest = self.isTracking;
    }
    
    // 트래킹 중이 아니면 임시로 위치 업데이트 시작
    if (!self.isTracking) {
        [self.locationManager startUpdatingLocation];
        RCTLogInfo(@"[RNRidableGpsTracker] 📍 Temporary location updates started for getCurrentLocation");
    }
    
    // 타임아웃 타이머 (10초)
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        @synchronized(self) {
            if (self.locationRequestReject) {
                RCTLogWarn(@"[RNRidableGpsTracker] ⚠️ getCurrentLocation timed out");
                
                self.locationRequestReject(@"TIMEOUT", @"Location request timed out", nil);
                self.locationRequestResolve = nil;
                self.locationRequestReject = nil;
                
                // 트래킹 중이 아니었다면 위치 업데이트 중지
                if (!self.wasTrackingBeforeRequest) {
                    [self.locationManager stopUpdatingLocation];
                    RCTLogInfo(@"[RNRidableGpsTracker] 📍 Temporary location updates stopped (timeout)");
                }
            }
        }
    });
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
        @"isPaused": @(self.isPaused),
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

RCT_EXPORT_METHOD(getAvailableSensors:(RCTPromiseResolveBlock)resolve
                  reject:(RCTPromiseRejectBlock)reject)
{
    // 가속계
    BOOL accelerometerAvailable = self.motionManager.isAccelerometerAvailable;
    
    // 자이로스코프
    BOOL gyroscopeAvailable = self.motionManager.isGyroAvailable;
    
    // 자기장 센서
    BOOL magnetometerAvailable = self.motionManager.isMagnetometerAvailable;
    
    // 조도 센서 (iOS는 UIScreen brightness 사용, 항상 사용 가능)
    BOOL lightAvailable = YES;
    
    // 소음 센서 (AVAudioSession 사용, 권한 필요)
    BOOL noiseAvailable = NO;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    AVAudioSessionRecordPermission permission = [audioSession recordPermission];
    if (permission == AVAudioSessionRecordPermissionGranted) {
        // 권한이 있으면 하드웨어 가용성 확인
        noiseAvailable = YES;  // iOS에서는 권한이 있으면 일반적으로 사용 가능
    } else if (permission == AVAudioSessionRecordPermissionUndetermined) {
        // 권한이 결정되지 않았으면 하드웨어는 사용 가능할 수 있음
        noiseAvailable = YES;
    }
    
    NSDictionary *result = @{
        @"accelerometer": @(accelerometerAvailable),
        @"gyroscope": @(gyroscopeAvailable),
        @"magnetometer": @(magnetometerAvailable),
        @"light": @(lightAvailable),
        @"noise": @(noiseAvailable)
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
    
    self.lastRawLatitude = location.coordinate.latitude;
    self.lastRawLongitude = location.coordinate.longitude;
    if (location.verticalAccuracy >= 0) {
        self.lastRawAltitude = location.altitude;
    } else {
        self.lastRawAltitude = NAN;
    }
    self.hasLastRawLocation = YES;
    
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
    
    // getCurrentLocation 콜백 처리
    @synchronized(self) {
        if (self.locationRequestResolve) {
            RCTLogInfo(@"[RNRidableGpsTracker] ✅ getCurrentLocation resolved");
            
            self.locationRequestResolve([self convertLocationToDict:processedLocation 
                                                        withNewFlag:YES 
                                                    currentAltitude:currentAltitude
                                                 includeSensorData:NO]);
            
            self.locationRequestResolve = nil;
            self.locationRequestReject = nil;
            
            // 트래킹 중이 아니었다면 위치 업데이트 중지
            if (!self.wasTrackingBeforeRequest) {
                [self.locationManager stopUpdatingLocation];
                RCTLogInfo(@"[RNRidableGpsTracker] 📍 Temporary location updates stopped");
            }
        }
    }
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
    
    // getCurrentLocation 콜백 에러 처리
    @synchronized(self) {
        if (self.locationRequestReject) {
            self.locationRequestReject(@"LOCATION_ERROR", error.localizedDescription, error);
            self.locationRequestResolve = nil;
            self.locationRequestReject = nil;
            
            if (!self.wasTrackingBeforeRequest) {
                [self.locationManager stopUpdatingLocation];
            }
        }
    }
    
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
                                                            currentAltitude:currentAltitude
                                                         includeSensorData:YES]];
        
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
                    includeSensorData:(BOOL)includeSensorData
{
    // ✅ 운동 타입 / Kalman 필터와 관계없이, speed는 항상 원본 GPS speed(m/s) 기반으로 전송
    double rawSpeed = (location.speed >= 0) ? location.speed : 0.0;

    // Pause 중이면 경과 시간 업데이트 안 함
    if (!self.isPaused) {
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        [self updateElapsedTimeWithTimestamp:now];
    }
    
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:@{
        @"latitude": @(location.coordinate.latitude),
        @"longitude": @(location.coordinate.longitude),
        @"altitude": @(location.altitude),
        @"accuracy": @(location.horizontalAccuracy),
        // ✅ Android와 동일하게, 항상 원본 GPS speed(m/s)를 사용
        @"speed": @(rawSpeed),
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
        @"isMoving": @(self.isCurrentlyMoving)
    }];
    
    double rawLatitude = self.hasLastRawLocation ? self.lastRawLatitude : location.coordinate.latitude;
    double rawLongitude = self.hasLastRawLocation ? self.lastRawLongitude : location.coordinate.longitude;
    dict[@"rawLatitude"] = @(rawLatitude);
    dict[@"rawLongitude"] = @(rawLongitude);
    
    double rawAltitudeCandidate = NAN;
    if (self.hasLastRawLocation && !isnan(self.lastRawAltitude)) {
        rawAltitudeCandidate = self.lastRawAltitude;
    } else if (location.verticalAccuracy >= 0) {
        rawAltitudeCandidate = location.altitude;
    }
    if (!isnan(rawAltitudeCandidate)) {
        dict[@"rawAltitude"] = @(rawAltitudeCandidate);
    }
    
    // 기압계 데이터
    if (includeSensorData) {
        if (self.lastAltitudeData && self.hasStartGpsAltitude) {
            double relativeAltitude = [self.lastAltitudeData.relativeAltitude doubleValue];
            double pressure = [self.lastAltitudeData.pressure doubleValue];
            
            dict[@"enhancedAltitude"] = @(currentAltitude);
            dict[@"relativeAltitude"] = @(relativeAltitude);
            dict[@"pressure"] = @(pressure);
        } else {
            dict[@"enhancedAltitude"] = @(currentAltitude);
        }
        
        double grade = [self resolveGradeForLocation:location
                                     currentAltitude:currentAltitude
                              updateStationaryState:YES];
        dict[@"grade"] = @(grade);
        dict[@"gradeCategory"] = [self getGradeCategory:grade];
    }
    
    // 모션 분석 결과만 전송 (Raw 센서 데이터 제거됨)
    if (includeSensorData && (self.useAccelerometer || self.useGyroscope)) {
        NSDictionary *motionAnalysis = [self generateMotionAnalysis];
        if (motionAnalysis) {
            dict[@"motionAnalysis"] = motionAnalysis;
        }
    }
    
    // 광센서 데이터
    if (includeSensorData && self.useLight && self.lastLuxTimestamp > 0) {
        dict[@"light"] = @{
            @"lux": @(self.currentLux),
            @"condition": [self getLightCondition:self.currentLux],
            @"isLowLight": @(self.currentLux < 50)
        };
    }
    
    // 소음 데이터
    if (includeSensorData && self.useNoise && self.lastDecibelTimestamp > 0 && self.currentDecibel > 0) {
        dict[@"noise"] = @{
            @"decibel": @(self.currentDecibel),
            @"noiseLevel": [self getNoiseLevel:self.currentDecibel]
        };
    }
    
    // 자기장 데이터
    if (includeSensorData && self.useMagnetometer && self.lastMagTimestamp > 0) {
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

- (void)updateElapsedTimeWithTimestamp:(NSTimeInterval)timestamp
{
    if (self.sessionStartTime <= 0) {
        return;
    }
    
    if (self.lastElapsedUpdateTime <= 0) {
        self.lastElapsedUpdateTime = self.sessionStartTime;
    }
    
    if (timestamp < self.lastElapsedUpdateTime) {
        // 시계가 뒤로 간 경우 현재 시간으로 리셋
        self.lastElapsedUpdateTime = timestamp;
        return;
    }
    
    NSTimeInterval delta = timestamp - self.lastElapsedUpdateTime;
    if (delta > 0) {
        self.sessionElapsedTime += delta;
        self.lastElapsedUpdateTime = timestamp;
    }
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
    
    // AudioSession을 한 번만 설정 (PlayAndRecord + MixWithOthers)
    if (!self.audioSession) {
        self.audioSession = [AVAudioSession sharedInstance];
        NSError *error = nil;

        // 같은 앱 내 오디오 재생을 유지하고, 마이크 + 스피커 동시 사용
        // ✅ 블루투스 오디오 허용 (헤드셋/이어폰 + 스피커 모두 지원)
        [self.audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                           withOptions:AVAudioSessionCategoryOptionMixWithOthers 
                                    | AVAudioSessionCategoryOptionAllowBluetooth
                                    | AVAudioSessionCategoryOptionAllowBluetoothA2DP
                                 error:&error];
        if (error) {
            RCTLogError(@"Audio session error: %@", error);
            return;
        }

        // 소음 측정에 적합한 모드 (원치 않으면 생략 가능)
        [self.audioSession setMode:AVAudioSessionModeMeasurement error:&error];
        if (error) {
            RCTLogError(@"Audio session mode error: %@", error);
            return;
        }

        [self.audioSession setActive:YES error:&error];
        if (error) {
            RCTLogError(@"Audio session activate error: %@", error);
            return;
        }
    }
    
    // AVAudioRecorder를 한 번만 생성하고 재사용
    if (!self.noiseRecorder) {
        NSDictionary *settings = @{
            AVFormatIDKey: @(kAudioFormatLinearPCM), // 더 가벼운 포맷
            AVSampleRateKey: @8000.0, // 44100 -> 8000 Hz
            AVNumberOfChannelsKey: @1,
            AVLinearPCMBitDepthKey: @16,
            AVLinearPCMIsBigEndianKey: @NO,
            AVLinearPCMIsFloatKey: @NO
        };
        
        NSURL *url = [NSURL fileURLWithPath:@"/dev/null"];
        NSError *error = nil;
        self.noiseRecorder = [[AVAudioRecorder alloc] initWithURL:url 
                                                          settings:settings 
                                                             error:&error];
        
        if (error || !self.noiseRecorder) {
            RCTLogError(@"Audio recorder error: %@", error);
            return;
        }
        
        [self.noiseRecorder prepareToRecord];
        self.noiseRecorder.meteringEnabled = YES;
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
    
    // Recorder 정리
    if (self.noiseRecorder) {
        [self.noiseRecorder stop];
        self.noiseRecorder = nil;
    }
    
    // AudioSession 비활성화
    if (self.audioSession) {
        [self.audioSession setActive:NO error:nil];
        self.audioSession = nil;
    }
    
    self.currentDecibel = 0.0;
    self.lastDecibelTimestamp = 0;
    RCTLogInfo(@"🎤 Noise measurement stopped");
}

- (void)measureNoiseLevel
{
    // 백그라운드 스레드에서 실행
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (!self.noiseRecorder || !self.audioSession) {
            return;
        }
        
        // 이미 녹음 중이면 재시작
        if (self.noiseRecorder.isRecording) {
            [self.noiseRecorder stop];
        }
        
        [self.noiseRecorder record];
        
        // 짧은 대기 시간 (0.05초로 단축)
        usleep(50000); // 0.05초
        
        [self.noiseRecorder updateMeters];
        
        // averagePowerForChannel: -160 ~ 0 dB 범위
        float averagePower = [self.noiseRecorder averagePowerForChannel:0];
        
        // -160 ~ 0 범위를 0 ~ 120 dB로 변환
        float decibel = MAX(0, MIN(120, averagePower + 120));
        
        // 메인 스레드에서 값 업데이트
        dispatch_async(dispatch_get_main_queue(), ^{
            self.currentDecibel = decibel;
            self.lastDecibelTimestamp = [[NSDate date] timeIntervalSince1970];
        });
        
        [self.noiseRecorder stop];
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