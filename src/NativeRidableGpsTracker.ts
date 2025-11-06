import type { TurboModule } from "react-native"
import { TurboModuleRegistry } from "react-native"

export interface Spec extends TurboModule {
  configure(config: {
    distanceFilter?: number
    desiredAccuracy?: string
    interval?: number
    fastestInterval?: number
    activityType?: string
    exerciseType?: string // 🆕 운동 유형 추가
    advancedTracking?: boolean // 🆕 고급 추적 모드
    allowsBackgroundLocationUpdates?: boolean
    showsBackgroundLocationIndicator?: boolean
    pausesLocationUpdatesAutomatically?: boolean
  }): Promise<void>

  start(): Promise<void>
  stop(): Promise<void>

  getCurrentLocation(): Promise<{
    latitude: number
    longitude: number
    altitude: number
    enhancedAltitude?: number
    relativeAltitude?: number
    pressure?: number
    accuracy: number
    speed: number
    bearing: number
    timestamp: number
    isNewLocation: boolean
    isKalmanFiltered?: boolean
    isMoving: boolean // 🆕 이동 상태

    // 🆕 Grade 데이터
    grade?: number
    gradeCategory?: string

    // 🆕 세션 통계
    sessionDistance?: number
    sessionElevationGain?: number
    sessionElevationLoss?: number
    sessionMovingTime?: number
    sessionElapsedTime?: number
    sessionMaxSpeed?: number
    sessionAvgSpeed?: number
    sessionMovingAvgSpeed?: number

    // 🆕 가속계 데이터 (advancedTracking=true일 때만)
    accelerometer?: {
      x: number
      y: number
      z: number
      magnitude: number
    }

    // 🆕 자이로스코프 데이터 (advancedTracking=true일 때만)
    gyroscope?: {
      x: number
      y: number
      z: number
      rotationRate: number
    }

    // 🆕 운동 분석 데이터 (advancedTracking=true일 때만)
    motionAnalysis?: {
      roadSurfaceQuality: string
      vibrationIntensity: number
      corneringIntensity: number
      inclineAngle: number
      isClimbing: boolean
      isDescending: boolean
      verticalAcceleration: number
    }
  }>

  checkStatus(): Promise<{
    isRunning: boolean
    isAuthorized: boolean
    authorizationStatus: string
    isBarometerAvailable: boolean
    isAccelerometerAvailable?: boolean // 🆕
    isGyroscopeAvailable?: boolean // 🆕
    isServiceBound?: boolean
    exerciseType: string
    advancedTracking?: boolean // 🆕
    isKalmanEnabled?: boolean
    useKalmanFilter?: boolean
  }>

  requestPermissions(): Promise<boolean>
  openLocationSettings(): void

  // Event emitter methods
  addListener(eventName: string): void
  removeListeners(count: number): void
  enableListeners(): void
  disableListeners(): void
}

export default TurboModuleRegistry.getEnforcing<Spec>("RNRidableGpsTracker")
