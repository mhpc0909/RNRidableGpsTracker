import { NativeEventEmitter, NativeModules, Platform } from "react-native"
import type { GpsTrackerConfig, LocationData, TrackerStatus, LocationEventCallback, ErrorEventCallback, AuthorizationChangedCallback, ExerciseType, RoadSurfaceQuality, GradeCategory, MotionAnalysis, SessionStats, MagnetometerData, LightData, NoiseData, RNRidableGpsTrackerModule } from "./types"

// 🆕 헬퍼 클래스 export
export { MotionAnalyzer, SensorDataProcessor, SessionAnalyzer, GradeAnalyzer, MagnetometerAnalyzer, LightAnalyzer, NoiseAnalyzer } from "./types"

// 타입 export
export type { GpsTrackerConfig, LocationData, TrackerStatus, LocationEventCallback, ErrorEventCallback, AuthorizationChangedCallback, ExerciseType, RoadSurfaceQuality, GradeCategory, MotionAnalysis, SessionStats, MagnetometerData, LightData, NoiseData, RNRidableGpsTrackerModule }

// enum export
export { ExerciseType } from "./types"

// Native Module
const LINKING_ERROR = `The package 'react-native-ridable-gps-tracker' doesn't seem to be linked. Make sure: \n\n` + Platform.select({ ios: "- Run 'pod install'\n", default: "" }) + "- Rebuild the app after installing the package\n" + "- If you are using Expo, run 'npx expo prebuild'\n"

const RNRidableGpsTracker: RNRidableGpsTrackerModule = NativeModules.RNRidableGpsTracker
  ? NativeModules.RNRidableGpsTracker
  : new Proxy(
      {},
      {
        get() {
          throw new Error(LINKING_ERROR)
        },
      }
    )

const eventEmitter = new NativeEventEmitter(RNRidableGpsTracker as any)

// GPS Tracker Class
export class GpsTracker {
  private static locationListener: any = null
  private static errorListener: any = null
  private static authorizationListener: any = null

  /**
   * GPS 추적 설정
   */
  static async configure(config: GpsTrackerConfig): Promise<void> {
    return RNRidableGpsTracker.configure(config)
  }

  /**
   * GPS 추적 시작
   */
  static async start(): Promise<void> {
    return RNRidableGpsTracker.start()
  }

  /**
   * GPS 추적 중지
   */
  static async stop(): Promise<void> {
    return RNRidableGpsTracker.stop()
  }

  /**
   * 현재 위치 가져오기
   */
  static async getCurrentLocation(): Promise<LocationData> {
    return RNRidableGpsTracker.getCurrentLocation()
  }

  /**
   * 상태 확인
   */
  static async checkStatus(): Promise<TrackerStatus> {
    return RNRidableGpsTracker.checkStatus()
  }

  /**
   * 권한 요청
   */
  static async requestPermissions(): Promise<boolean> {
    return RNRidableGpsTracker.requestPermissions()
  }

  /**
   * 위치 설정 열기
   */
  static openLocationSettings(): void {
    RNRidableGpsTracker.openLocationSettings()
  }

  /**
   * 위치 이벤트 리스너 등록
   */
  static addLocationListener(callback: LocationEventCallback): void {
    this.removeLocationListener()
    this.locationListener = eventEmitter.addListener("location", callback)
  }

  /**
   * 에러 이벤트 리스너 등록
   */
  static addErrorListener(callback: ErrorEventCallback): void {
    this.removeErrorListener()
    this.errorListener = eventEmitter.addListener("error", callback)
  }

  /**
   * 권한 변경 이벤트 리스너 등록
   */
  static addAuthorizationListener(callback: AuthorizationChangedCallback): void {
    this.removeAuthorizationListener()
    this.authorizationListener = eventEmitter.addListener("authorizationChanged", callback)
  }

  /**
   * 위치 리스너 제거
   */
  static removeLocationListener(): void {
    if (this.locationListener) {
      this.locationListener.remove()
      this.locationListener = null
    }
  }

  /**
   * 에러 리스너 제거
   */
  static removeErrorListener(): void {
    if (this.errorListener) {
      this.errorListener.remove()
      this.errorListener = null
    }
  }

  /**
   * 권한 리스너 제거
   */
  static removeAuthorizationListener(): void {
    if (this.authorizationListener) {
      this.authorizationListener.remove()
      this.authorizationListener = null
    }
  }

  /**
   * 모든 리스너 제거
   */
  static removeAllListeners(): void {
    this.removeLocationListener()
    this.removeErrorListener()
    this.removeAuthorizationListener()
  }
}

// 🆕 편의 함수들
export const GpsTrackerUtils = {
  /**
   * m/s를 km/h로 변환
   */
  metersPerSecondToKmh(speed: number): number {
    return speed * 3.6
  },

  /**
   * 미터를 킬로미터로 변환
   */
  metersToKm(distance: number): string {
    return (distance / 1000).toFixed(2)
  },

  /**
   * 초를 분:초 형식으로 변환
   */
  secondsToMinutesSeconds(seconds: number): string {
    const mins = Math.floor(seconds / 60)
    const secs = Math.floor(seconds % 60)
    return `${mins}:${secs.toString().padStart(2, "0")}`
  },

  /**
   * 초를 시:분:초 형식으로 변환
   */
  secondsToHMS(seconds: number): string {
    const hours = Math.floor(seconds / 3600)
    const minutes = Math.floor((seconds % 3600) / 60)
    const secs = Math.floor(seconds % 60)

    if (hours > 0) {
      return `${hours}:${minutes.toString().padStart(2, "0")}:${secs.toString().padStart(2, "0")}`
    }
    return `${minutes}:${secs.toString().padStart(2, "0")}`
  },

  /**
   * 페이스 계산 (분/km)
   */
  calculatePace(speedMs: number): string {
    if (speedMs <= 0) return "--:--"
    const paceMinPerKm = 1000 / (speedMs * 60)
    const mins = Math.floor(paceMinPerKm)
    const secs = Math.floor((paceMinPerKm - mins) * 60)
    return `${mins}:${secs.toString().padStart(2, "0")}`
  },

  /**
   * 이동 효율성 계산 (%)
   */
  calculateEfficiency(movingTime: number, elapsedTime: number): number {
    if (elapsedTime === 0) return 0
    return (movingTime / elapsedTime) * 100
  },

  /**
   * Grade 이모지 가져오기
   */
  getGradeEmoji(grade: number): string {
    const absGrade = Math.abs(grade)
    if (absGrade < 2) return "➡️"
    if (grade > 0) {
      if (absGrade < 5) return "⬆️"
      if (absGrade < 8) return "↗️"
      if (absGrade < 12) return "⏫"
      return "🔺"
    } else {
      if (absGrade < 5) return "⬇️"
      if (absGrade < 8) return "↘️"
      if (absGrade < 12) return "⏬"
      return "🔻"
    }
  },

  /**
   * 방위각을 방향 문자열로 변환
   */
  getDirectionFromHeading(heading: number): string {
    const directions = ["북", "북동", "동", "남동", "남", "남서", "서", "북서"]
    const index = Math.round(heading / 45) % 8
    return directions[index]
  },

  /**
   * 방위각 이모지 가져오기
   */
  getDirectionEmoji(heading: number): string {
    const emojis = ["⬆️", "↗️", "➡️", "↘️", "⬇️", "↙️", "⬅️", "↖️"]
    const index = Math.round(heading / 45) % 8
    return emojis[index]
  },
}

export default GpsTracker
