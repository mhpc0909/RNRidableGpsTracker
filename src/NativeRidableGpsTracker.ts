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
    accuracy: number
    speed: number
    bearing: number
    timestamp: number
  }>

  checkStatus(): Promise<{
    isRunning: boolean
    isAuthorized: boolean
    authorizationStatus: string
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
