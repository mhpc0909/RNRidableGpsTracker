// RNRidableGpsTracker 타입 정의

// 운동 타입 (enum 방식)
export enum ExerciseType {
  BICYCLE = "bicycle",
  RUNNING = "running",
  HIKING = "hiking",
  WALKING = "walking",
}

export type RoadSurfaceQuality = "smooth" | "rough" | "very_rough"
export type GradeCategory = "flat" | "gentle" | "moderate" | "steep" | "very_steep"

export interface GpsTrackerConfig {
  distanceFilter?: number
  interval?: number
  fastestInterval?: number
  desiredAccuracy?: "high" | "medium" | "low"
  exerciseType?: ExerciseType
  // 🆕 개별 센서 제어
  useAccelerometer?: boolean // 가속계 (진동, 경사 분석)
  useGyroscope?: boolean // 자이로스코프 (코너링 분석)
  useMagnetometer?: boolean // 자기장 센서 (방향, 자기장 강도)
  useLight?: boolean // 광센서 (조도 측정)
  useNoise?: boolean // 소음 측정 (RECORD_AUDIO 권한 필요)
  allowsBackgroundLocationUpdates?: boolean
  showsBackgroundLocationIndicator?: boolean
  pausesLocationUpdatesAutomatically?: boolean
}

// 🆕 운동 분석 데이터
export interface MotionAnalysis {
  roadSurfaceQuality: RoadSurfaceQuality // 노면 품질
  vibrationLevel: number // 원본 진동 수치 (m/s²)
  vibrationIntensity: number // 정규화된 진동 강도 (0.0 ~ 1.0)
  corneringIntensity: number // 코너링 강도 (0.0 ~ 1.0)
  inclineAngle: number // 경사각 (-90 ~ 90 도)
  isClimbing: boolean // 오르막 여부
  isDescending: boolean // 내리막 여부
  verticalAcceleration: number // 수직 가속도 (m/s²)
}

// 🆕 자기장 센서 데이터
export interface MagnetometerData {
  heading: number // 방향 (0-360도, 자북 기준)
  magneticFieldStrength: number // 자기장 강도 (μT)
  x: number // X축 자기장
  y: number // Y축 자기장
  z: number // Z축 자기장
}

// 🆕 광센서 데이터
export interface LightData {
  lux: number // 조도 (lux)
  condition: "dark" | "dim" | "indoor" | "overcast" | "daylight" | "bright_sunlight" // 조도 상태
  isLowLight: boolean // 어두움 여부 (< 50 lux)
}

// 🆕 소음 데이터
export interface NoiseData {
  decibel: number // 소음 레벨 (dB)
  noiseLevel: "very_quiet" | "quiet" | "moderate" | "noisy" | "very_noisy" | "dangerously_loud" // 소음 상태
}

// 🆕 세션 통계 데이터
export interface SessionStats {
  sessionDistance: number // 이동 거리 (m)
  sessionElevationGain: number // 획득 고도 (m)
  sessionElevationLoss: number // 상실 고도 (m)
  sessionMovingTime: number // 이동 시간 (초) - 속도 ≥ 0.5 m/s
  sessionElapsedTime: number // 총 경과 시간 (초)
  sessionMaxSpeed: number // 최고 속도 (m/s)
  sessionAvgSpeed: number // 평균 속도 (m/s) - elapsed 기준
  sessionMovingAvgSpeed: number // 이동 평균 속도 (m/s) - moving 기준
}

export interface LocationData {
  latitude: number
  longitude: number
  altitude: number
  accuracy: number
  speed: number
  bearing: number
  timestamp: number
  isNewLocation: boolean
  isKalmanFiltered: boolean
  isMoving: boolean // 이동 상태 (필터링된 속도/거리 기반)

  // 기압계 데이터 (선택적)
  enhancedAltitude?: number // GPS + 기압계 보정 고도
  relativeAltitude?: number // 상대 고도 변화
  pressure?: number // 기압 (hPa)

  // Grade 데이터
  grade?: number // 경사도 (%)
  gradeCategory?: GradeCategory // 경사도 카테고리

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
  motionAnalysis?: MotionAnalysis

  // 🆕 자기장 센서 데이터 (useMagnetometer=true일 때)
  magnetometer?: MagnetometerData

  // 🆕 광센서 데이터 (useLight=true일 때)
  light?: LightData

  // 🆕 소음 데이터 (useNoise=true일 때)
  noise?: NoiseData
}

export interface TrackerStatus {
  isRunning: boolean
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
}

// React Native 이벤트 리스너 타입
export type LocationEventCallback = (data: LocationData) => void
export type ErrorEventCallback = (error: { code: number; message: string }) => void
export type AuthorizationChangedCallback = (data: { status: string }) => void

// 🆕 운동 유형별 분석 도우미 함수
export class MotionAnalyzer {
  /**
   * 자전거 타기 분석
   */
  static analyzeCycling(location: LocationData): {
    roadCondition: string
    corneringLevel: string
    climbingIntensity: string
  } | null {
    if (!location.motionAnalysis) return null

    const { roadSurfaceQuality, corneringIntensity, inclineAngle } = location.motionAnalysis

    return {
      roadCondition: roadSurfaceQuality === "smooth" ? "양호" : roadSurfaceQuality === "rough" ? "보통" : "불량",
      corneringLevel: corneringIntensity < 0.3 ? "직선" : corneringIntensity < 0.6 ? "완만한 커브" : "급커브",
      climbingIntensity: Math.abs(inclineAngle) < 5 ? "평지" : inclineAngle > 10 ? "가파른 오르막" : inclineAngle > 5 ? "완만한 오르막" : inclineAngle < -10 ? "가파른 내리막" : "완만한 내리막",
    }
  }

  /**
   * 러닝 분석
   */
  static analyzeRunning(location: LocationData): {
    strideConsistency: string
    verticalOscillation: string
  } | null {
    if (!location.motionAnalysis) return null

    const { vibrationIntensity, verticalAcceleration } = location.motionAnalysis

    return {
      strideConsistency: vibrationIntensity < 0.3 ? "일정함" : vibrationIntensity < 0.6 ? "보통" : "불규칙",
      verticalOscillation: Math.abs(verticalAcceleration) < 2 ? "낮음" : Math.abs(verticalAcceleration) < 4 ? "보통" : "높음",
    }
  }

  /**
   * 하이킹 분석
   */
  static analyzeHiking(location: LocationData): {
    terrainDifficulty: string
    elevationChange: string
  } | null {
    if (!location.motionAnalysis || !location.relativeAltitude) return null

    const { vibrationIntensity, inclineAngle } = location.motionAnalysis
    const { relativeAltitude } = location

    const difficulty = vibrationIntensity + Math.abs(inclineAngle) / 45

    return {
      terrainDifficulty: difficulty < 0.4 ? "쉬움" : difficulty < 0.7 ? "보통" : "어려움",
      elevationChange: relativeAltitude > 50 ? `+${relativeAltitude.toFixed(0)}m 상승` : relativeAltitude < -50 ? `${relativeAltitude.toFixed(0)}m 하강` : "평지 구간",
    }
  }
}

// 🆕 세션 통계 분석 도우미
export class SessionAnalyzer {
  /**
   * 이동 효율성 계산 (%)
   */
  static calculateMovingEfficiency(location: LocationData): number | null {
    if (!location.sessionMovingTime || !location.sessionElapsedTime) return null
    if (location.sessionElapsedTime === 0) return 0
    return (location.sessionMovingTime / location.sessionElapsedTime) * 100
  }

  /**
   * 정지 시간 계산 (초)
   */
  static calculateStoppedTime(location: LocationData): number | null {
    if (!location.sessionMovingTime || !location.sessionElapsedTime) return null
    return location.sessionElapsedTime - location.sessionMovingTime
  }

  /**
   * 운동 요약 생성
   */
  static generateSummary(location: LocationData): {
    distance: string
    duration: string
    movingTime: string
    avgSpeed: string
    movingAvgSpeed: string
    elevationGain: string
    maxSpeed: string
    efficiency: string
  } | null {
    if (!location.sessionDistance || !location.sessionElapsedTime) return null

    const distanceKm = (location.sessionDistance / 1000).toFixed(2)
    const durationMin = Math.floor(location.sessionElapsedTime / 60)
    const movingMin = Math.floor((location.sessionMovingTime || 0) / 60)
    const avgSpeedKmh = ((location.sessionAvgSpeed || 0) * 3.6).toFixed(1)
    const movingAvgSpeedKmh = ((location.sessionMovingAvgSpeed || 0) * 3.6).toFixed(1)
    const elevationM = (location.sessionElevationGain || 0).toFixed(0)
    const maxSpeedKmh = ((location.sessionMaxSpeed || 0) * 3.6).toFixed(1)
    const efficiency = this.calculateMovingEfficiency(location)?.toFixed(0) || "0"

    return {
      distance: `${distanceKm} km`,
      duration: `${durationMin} 분`,
      movingTime: `${movingMin} 분`,
      avgSpeed: `${avgSpeedKmh} km/h`,
      movingAvgSpeed: `${movingAvgSpeedKmh} km/h`,
      elevationGain: `+${elevationM} m`,
      maxSpeed: `${maxSpeedKmh} km/h`,
      efficiency: `${efficiency}%`,
    }
  }
}

// 🆕 센서 데이터 활용 예시 클래스
export class SensorDataProcessor {
  /**
   * 노면 품질 점수 계산 (0-100)
   */
  static calculateRoadQualityScore(data: LocationData): number | null {
    if (!data.motionAnalysis) return null

    const { roadSurfaceQuality, vibrationIntensity } = data.motionAnalysis
    const baseScore = roadSurfaceQuality === "smooth" ? 90 : roadSurfaceQuality === "rough" ? 60 : 30
    const vibrationPenalty = vibrationIntensity * 20

    return Math.max(0, Math.min(100, baseScore - vibrationPenalty))
  }

  /**
   * 코너링 위험도 평가 (0-100)
   */
  static calculateCorneringRisk(data: LocationData): number | null {
    if (!data.motionAnalysis || !data.speed) return null

    const { corneringIntensity } = data.motionAnalysis
    const speedKmh = data.speed * 3.6
    const speedFactor = Math.min(speedKmh / 50, 1)
    const risk = corneringIntensity * speedFactor * 100

    return Math.min(100, risk)
  }

  /**
   * 칼로리 소모량 추정
   */
  static estimateCaloriesBurn(data: LocationData, userWeightKg: number): number | null {
    if (!data.sessionElapsedTime) return null

    const speedKmh = data.speed * 3.6
    const gradePercent = data.grade || 0

    let met = 0
    if (speedKmh > 0) {
      met = 3.5 + speedKmh / 10 + Math.abs(gradePercent) / 10
      if (data.motionAnalysis) {
        met += data.motionAnalysis.vibrationIntensity * 0.5
      }
    }

    const hours = data.sessionElapsedTime / 3600
    return met * userWeightKg * hours
  }
}

// 🆕 Grade 분석 도우미
export class GradeAnalyzer {
  /**
   * Grade 설명 가져오기
   */
  static getGradeDescription(grade: number): string {
    const absGrade = Math.abs(grade)
    if (absGrade < 2) return "평지"
    if (absGrade < 5) return grade > 0 ? "완만한 오르막" : "완만한 내리막"
    if (absGrade < 8) return grade > 0 ? "중간 오르막" : "중간 내리막"
    if (absGrade < 12) return grade > 0 ? "가파른 오르막" : "가파른 내리막"
    return grade > 0 ? "매우 가파른 오르막" : "매우 가파른 내리막"
  }

  /**
   * Grade 색상 가져오기 (UI용)
   */
  static getGradeColor(grade: number): string {
    const absGrade = Math.abs(grade)
    if (absGrade < 2) return "#4CAF50"
    if (absGrade < 5) return "#8BC34A"
    if (absGrade < 8) return "#FFC107"
    if (absGrade < 12) return "#FF9800"
    return "#F44336"
  }

  /**
   * Grade 난이도 (0-10)
   */
  static getGradeDifficulty(grade: number): number {
    const absGrade = Math.abs(grade)
    return Math.min(10, Math.floor(absGrade / 3))
  }
}

// 🆕 자기장 센서 분석 도우미
export class MagnetometerAnalyzer {
  /**
   * 방위각을 방향 문자열로 변환
   */
  static getDirectionFromHeading(heading: number): string {
    const directions = ["북", "북동", "동", "남동", "남", "남서", "서", "북서"]
    const index = Math.round(heading / 45) % 8
    return directions[index]
  }

  /**
   * 방위각 이모지 가져오기
   */
  static getDirectionEmoji(heading: number): string {
    const emojis = ["⬆️", "↗️", "➡️", "↘️", "⬇️", "↙️", "⬅️", "↖️"]
    const index = Math.round(heading / 45) % 8
    return emojis[index]
  }

  /**
   * GPS bearing과 자기장 heading 비교
   */
  static compareBearingAndHeading(
    gpsBearing: number,
    magneticHeading: number
  ): {
    difference: number
    isConsistent: boolean
    warning: string | null
  } {
    let diff = magneticHeading - gpsBearing
    if (diff > 180) diff -= 360
    if (diff < -180) diff += 360

    const absDiff = Math.abs(diff)

    return {
      difference: diff,
      isConsistent: absDiff < 15,
      warning: absDiff > 30 ? "자기 간섭 의심 (금속 물체, 전자기기)" : null,
    }
  }

  /**
   * 자기장 세기 평가
   */
  static evaluateMagneticFieldStrength(magnitude: number): {
    strength: string
    description: string
    environment: string
  } {
    if (magnitude < 25) {
      return { strength: "매우 약함", description: "자기 간섭 또는 센서 오류", environment: "unknown" }
    } else if (magnitude < 65) {
      return { strength: "정상", description: "지구 자기장 정상 범위", environment: "outdoor" }
    } else if (magnitude < 80) {
      return { strength: "약간 강함", description: "실내 또는 금속 근처", environment: "indoor" }
    } else if (magnitude < 150) {
      return { strength: "강함", description: "금속 구조물 근처 (터널, 철교)", environment: "near_metal_structure" }
    } else {
      return { strength: "매우 강함", description: "강한 자기장 감지 (전자기기)", environment: "strong_interference" }
    }
  }
}

// 🆕 광센서 분석 도우미
export class LightAnalyzer {
  /**
   * 조도 설명 가져오기
   */
  static getLightDescription(lux: number): string {
    if (lux < 10) return "어두움 (가로등 없는 밤)"
    if (lux < 50) return "희미함 (가로등 아래)"
    if (lux < 200) return "실내 조명"
    if (lux < 1000) return "흐린 날씨"
    if (lux < 10000) return "맑은 날씨"
    return "밝은 햇빛"
  }

  /**
   * 야간 라이딩 여부 판단
   */
  static isNightRiding(lux: number): boolean {
    return lux < 50
  }

  /**
   * 라이트 권장 여부
   */
  static shouldUseLights(lux: number): boolean {
    return lux < 200
  }
}

// 🆕 소음 분석 도우미
export class NoiseAnalyzer {
  /**
   * 소음 설명 가져오기
   */
  static getNoiseDescription(decibel: number): string {
    if (decibel < 30) return "매우 조용함 (도서관)"
    if (decibel < 50) return "조용함 (일반 대화)"
    if (decibel < 60) return "보통 (사무실)"
    if (decibel < 70) return "시끄러움 (번화가)"
    if (decibel < 85) return "매우 시끄러움 (지하철)"
    return "위험 수준 (청력 손상 가능)"
  }

  /**
   * 귀마개 권장 여부
   */
  static shouldUseEarplugs(decibel: number): boolean {
    return decibel > 85
  }

  /**
   * 환경 소음 평가
   */
  static evaluateEnvironmentNoise(decibel: number): {
    level: string
    recommendation: string
  } {
    if (decibel < 50) {
      return { level: "조용함", recommendation: "쾌적한 라이딩 환경" }
    } else if (decibel < 70) {
      return { level: "보통", recommendation: "일반적인 도심 환경" }
    } else if (decibel < 85) {
      return { level: "시끄러움", recommendation: "소음이 많은 구간" }
    } else {
      return { level: "매우 시끄러움", recommendation: "귀마개 착용 권장" }
    }
  }
}

// 모듈 인터페이스
export interface RNRidableGpsTrackerModule {
  configure(config: GpsTrackerConfig): Promise<void>
  start(): Promise<void>
  stop(): Promise<void>
  getCurrentLocation(): Promise<LocationData>
  checkStatus(): Promise<TrackerStatus>
  requestPermissions(): Promise<boolean>
  openLocationSettings(): void

  addListener(eventName: "location", callback: LocationEventCallback): void
  addListener(eventName: "error", callback: ErrorEventCallback): void
  addListener(eventName: "authorizationChanged", callback: AuthorizationChangedCallback): void
  removeListeners(count: number): void
}

// 사용 예시
export const UsageExample = {
  /**
   * 센서별 설정 예시
   */
  async setupSensorTracking() {
    const RNRidableGpsTracker = require("react-native").NativeModules.RNRidableGpsTracker as RNRidableGpsTrackerModule

    // 자전거 모드 + 센서 개별 제어
    await RNRidableGpsTracker.configure({
      exerciseType: ExerciseType.BICYCLE,
      useAccelerometer: true, // 진동, 경사 분석
      useGyroscope: true, // 코너링 분석
      useMagnetometer: true, // 방향 추적
      useLight: true, // 조도 측정
      useNoise: false, // 소음 측정 (권한 필요)
      interval: 1000,
      desiredAccuracy: "high",
    })

    await RNRidableGpsTracker.start()
  },
}

// 호환성을 위한 type alias
export type LocationConfig = GpsTrackerConfig
export type LocationStatus = TrackerStatus
