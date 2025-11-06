// RNRidableGpsTracker 타입 정의

// 운동 타입 (enum 방식 - 기존 코드 호환성)
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
  advancedTracking?: boolean // 🆕 고급 센서 추적
  allowsBackgroundLocationUpdates?: boolean
  showsBackgroundLocationIndicator?: boolean
  pausesLocationUpdatesAutomatically?: boolean
}

// 🆕 가속계 데이터
export interface AccelerometerData {
  x: number // X축 가속도 (m/s²)
  y: number // Y축 가속도 (m/s²)
  z: number // Z축 가속도 (m/s²)
  magnitude: number // 전체 가속도 크기
}

// 🆕 자이로스코프 데이터
export interface GyroscopeData {
  x: number // X축 회전 속도 (rad/s)
  y: number // Y축 회전 속도 (rad/s)
  z: number // Z축 회전 속도 (rad/s)
  rotationRate: number // 전체 회전 속도
}

// 🆕 운동 분석 데이터
export interface MotionAnalysis {
  roadSurfaceQuality: RoadSurfaceQuality // 노면 품질
  vibrationIntensity: number // 진동 강도 (0.0 ~ 1.0)
  corneringIntensity: number // 코너링 강도 (0.0 ~ 1.0)
  inclineAngle: number // 경사각 (-90 ~ 90 도)
  isClimbing: boolean // 오르막 여부
  isDescending: boolean // 내리막 여부
  verticalAcceleration: number // 수직 가속도 (m/s²)
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
  isMoving: boolean // 🆕 이동 상태 (속도 >= 0.5 m/s)

  // 기압계 데이터 (선택적)
  enhancedAltitude?: number // GPS + 기압계 보정 고도
  relativeAltitude?: number // 상대 고도 변화
  pressure?: number // 기압 (hPa)

  // 🆕 Grade 데이터
  grade?: number // 경사도 (%)
  gradeCategory?: GradeCategory // 경사도 카테고리

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
  accelerometer?: AccelerometerData

  // 🆕 자이로스코프 데이터 (advancedTracking=true일 때만)
  gyroscope?: GyroscopeData

  // 🆕 운동 분석 데이터 (advancedTracking=true일 때만)
  motionAnalysis?: MotionAnalysis
}

export interface TrackerStatus {
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
}

// React Native 이벤트 리스너 타입
export type LocationEventCallback = (data: LocationData) => void
export type ErrorEventCallback = (error: { code: number; message: string }) => void
export type AuthorizationChangedCallback = (data: { status: string }) => void

// 🆕 운동 유형별 분석 도우미 함수
export class MotionAnalyzer {
  /**
   * 자전거 타기 분석
   * - 노면 품질: 도로 상태 평가
   * - 코너링: 급커브 구간 감지
   * - 경사도: 오르막/내리막 강도 측정
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
   * - 보폭 일관성: 진동 패턴 분석
   * - 수직 진동: 착지 충격 평가
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
   * - 지형 난이도: 진동 + 경사도 종합
   * - 고도 변화: 상승/하강 추적
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
   * movingTime / elapsedTime * 100
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
   * 평균 속도 비교
   */
  static compareAverageSpeeds(location: LocationData): {
    avgSpeed: number
    movingAvgSpeed: number
    difference: number
    efficiencyLoss: number
  } | null {
    if (!location.sessionAvgSpeed || !location.sessionMovingAvgSpeed) return null

    return {
      avgSpeed: location.sessionAvgSpeed,
      movingAvgSpeed: location.sessionMovingAvgSpeed,
      difference: location.sessionMovingAvgSpeed - location.sessionAvgSpeed,
      efficiencyLoss: ((location.sessionMovingAvgSpeed - location.sessionAvgSpeed) / location.sessionMovingAvgSpeed) * 100,
    }
  }

  /**
   * Grade 기반 난이도 점수 (0-100)
   */
  static calculateDifficultyScore(location: LocationData): number | null {
    if (!location.sessionElevationGain || !location.sessionDistance) return null

    const elevationRatio = (location.sessionElevationGain / location.sessionDistance) * 100
    const score = Math.min(100, elevationRatio * 10)

    return score
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

    // 속도가 빠를수록, 코너링이 심할수록 위험도 증가
    const speedFactor = Math.min(speedKmh / 50, 1) // 50km/h 기준
    const risk = corneringIntensity * speedFactor * 100

    return Math.min(100, risk)
  }

  /**
   * 칼로리 소모량 추정 (운동 분석 데이터 기반)
   */
  static estimateCaloriesBurn(data: LocationData, userWeightKg: number): number | null {
    if (!data.sessionElapsedTime) return null

    const speedKmh = data.speed * 3.6
    const gradePercent = data.grade || 0

    // MET (Metabolic Equivalent) 계산
    let met = 0

    if (speedKmh > 0) {
      // 기본 MET + 경사도 보정
      met = 3.5 + speedKmh / 10 + Math.abs(gradePercent) / 10

      // 운동 분석 데이터로 추가 보정
      if (data.motionAnalysis) {
        met += data.motionAnalysis.vibrationIntensity * 0.5
      }
    }

    // 칼로리 = MET × 체중(kg) × 시간(시간)
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

    if (absGrade < 2) return "#4CAF50" // 녹색
    if (absGrade < 5) return "#8BC34A" // 연녹색
    if (absGrade < 8) return "#FFC107" // 노란색
    if (absGrade < 12) return "#FF9800" // 주황색
    return "#F44336" // 빨간색
  }

  /**
   * Grade 난이도 (0-10)
   */
  static getGradeDifficulty(grade: number): number {
    const absGrade = Math.abs(grade)
    return Math.min(10, Math.floor(absGrade / 3))
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

  // 이벤트 리스너
  addListener(eventName: "location", callback: LocationEventCallback): void
  addListener(eventName: "error", callback: ErrorEventCallback): void
  addListener(eventName: "authorizationChanged", callback: AuthorizationChangedCallback): void
  removeListeners(count: number): void
}

// 사용 예시
export const UsageExample = {
  /**
   * 고급 추적 설정 예시
   */
  async setupAdvancedTracking() {
    const RNRidableGpsTracker = require("react-native").NativeModules.RNRidableGpsTracker as RNRidableGpsTrackerModule

    // 자전거 모드 + 고급 센서 추적
    await RNRidableGpsTracker.configure({
      exerciseType: ExerciseType.BICYCLE,
      advancedTracking: true, // 🆕 가속계, 자이로스코프 활성화
      interval: 1000,
      fastestInterval: 1000,
      desiredAccuracy: "high",
    })

    // 위치 이벤트 리스너
    RNRidableGpsTracker.addListener("location", (data: LocationData) => {
      console.log("GPS:", data.latitude, data.longitude)

      // 🆕 이동 상태
      if (data.isMoving) {
        console.log("🟢 이동 중:", data.speed * 3.6, "km/h")
      } else {
        console.log("🟠 자동 멈춤 (속도 < 0.5 m/s)")
      }

      // 🆕 Grade 정보
      if (data.grade !== undefined) {
        console.log("경사도:", data.grade.toFixed(1), "%")
        console.log("카테고리:", data.gradeCategory)
        console.log("설명:", GradeAnalyzer.getGradeDescription(data.grade))
      }

      // 🆕 세션 통계
      const summary = SessionAnalyzer.generateSummary(data)
      if (summary) {
        console.log("거리:", summary.distance)
        console.log("경과 시간:", summary.duration)
        console.log("이동 시간:", summary.movingTime)
        console.log("평균 속도:", summary.avgSpeed)
        console.log("이동 평균:", summary.movingAvgSpeed)
        console.log("획득 고도:", summary.elevationGain)
        console.log("효율성:", summary.efficiency)
      }

      // 🆕 운동 분석 데이터 활용
      if (data.motionAnalysis) {
        const analysis = MotionAnalyzer.analyzeCycling(data)
        console.log("도로 상태:", analysis?.roadCondition)
        console.log("커브 강도:", analysis?.corneringLevel)
        console.log("경사도:", analysis?.climbingIntensity)

        // 노면 품질 점수
        const roadScore = SensorDataProcessor.calculateRoadQualityScore(data)
        console.log("노면 점수:", roadScore)

        // 코너링 위험도
        const cornerRisk = SensorDataProcessor.calculateCorneringRisk(data)
        console.log("코너 위험도:", cornerRisk)
      }

      // 🆕 칼로리 계산
      const calories = SensorDataProcessor.estimateCaloriesBurn(data, 70) // 70kg 기준
      if (calories) {
        console.log("소모 칼로리:", calories.toFixed(0), "kcal")
      }
    })

    await RNRidableGpsTracker.start()
  },
}

// index.ts와의 호환성을 위한 type alias
export type LocationConfig = GpsTrackerConfig
export type LocationStatus = TrackerStatus
