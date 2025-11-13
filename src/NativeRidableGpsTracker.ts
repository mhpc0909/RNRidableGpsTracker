import type { TurboModule } from "react-native"
import { TurboModuleRegistry } from "react-native"

export interface Spec extends TurboModule {
  configure(config: {
    distanceFilter?: number
    desiredAccuracy?: string
    interval?: number
    fastestInterval?: number
    activityType?: string
    exerciseType?: string
    // 🆕 개별 센서 제어 (advancedTracking 제거)
    useAccelerometer?: boolean
    useGyroscope?: boolean
    useMagnetometer?: boolean
    useLight?: boolean
    useNoise?: boolean
    allowsBackgroundLocationUpdates?: boolean
    showsBackgroundLocationIndicator?: boolean
    pausesLocationUpdatesAutomatically?: boolean
  }): Promise<void>

  start(): Promise<void>
  stop(): Promise<void>
  pause(): Promise<void>
  resume(): Promise<void>

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
    isMoving: boolean

    // Grade 데이터
    grade?: number
    gradeCategory?: string

    // 세션 통계
    sessionDistance?: number
    sessionElevationGain?: number
    sessionElevationLoss?: number
    sessionMovingTime?: number
    sessionElapsedTime?: number
    sessionMaxSpeed?: number
    sessionAvgSpeed?: number
    sessionMovingAvgSpeed?: number

    // 🆕 운동 분석 데이터 (가속계/자이로 사용 시)
    motionAnalysis?: {
      roadSurfaceQuality: string
      vibrationLevel: number // 🆕 원본 진동 수치 (m/s²)
      vibrationIntensity: number // 정규화된 진동 강도 (0-1)
      corneringIntensity: number
      inclineAngle: number
      isClimbing: boolean
      isDescending: boolean
      verticalAcceleration: number
    }

    // 🆕 자기장 센서 데이터 (useMagnetometer=true일 때)
    magnetometer?: {
      heading: number // 방향 (0-360도)
      magneticFieldStrength: number // 자기장 강도 (μT)
      x: number
      y: number
      z: number
    }

    // 🆕 광센서 데이터 (useLight=true일 때)
    light?: {
      lux: number // 조도 (lux)
      condition: string // "dark", "dim", "indoor", "overcast", "daylight", "bright_sunlight"
      isLowLight: boolean // 어두움 여부 (< 50 lux)
    }

    // 🆕 소음 데이터 (useNoise=true일 때, RECORD_AUDIO 권한 필요)
    noise?: {
      decibel: number // 소음 레벨 (dB)
      noiseLevel: string // "very_quiet", "quiet", "moderate", "noisy", "very_noisy", "dangerously_loud"
    }
  }>

  checkStatus(): Promise<{
    isRunning: boolean
    isPaused?: boolean
    isAuthorized: boolean
    authorizationStatus: string
    isBarometerAvailable: boolean
    isAccelerometerAvailable?: boolean
    isGyroscopeAvailable?: boolean
    isMagnetometerAvailable?: boolean
    isServiceBound?: boolean
    exerciseType: string
    // 🆕 개별 센서 사용 상태
    useAccelerometer?: boolean
    useGyroscope?: boolean
    useMagnetometer?: boolean
    useLight?: boolean
    useNoise?: boolean
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
