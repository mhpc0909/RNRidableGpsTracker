import { NativeEventEmitter, NativeModules, Platform } from "react-native"
import type { LocationConfig, LocationData, LocationStatus, LocationEventCallback } from "./types"

const LINKING_ERROR = `The package 'react-native-ridable-gps-tracker' doesn't seem to be linked. Make sure: \n\n` + Platform.select({ ios: "- Run 'pod install'\n", default: "" }) + "- Rebuild the app after installing the package\n"

const RidableGpsTrackerModule = NativeModules.RNRidableGpsTracker

if (!RidableGpsTrackerModule) {
  throw new Error(LINKING_ERROR)
}

// Create event emitter
const eventEmitter = new NativeEventEmitter(RidableGpsTrackerModule)

class RidableGpsTracker {
  private locationListener: any = null
  private errorListener: any = null
  private authListener: any = null
  private isListenersReady = false

  /**
   * Configure GPS tracking settings
   */
  async configure(config: LocationConfig): Promise<void> {
    return RidableGpsTrackerModule.configure(config)
  }

  /**
   * Start GPS tracking
   */
  async start(): Promise<void> {
    console.log("[RidableGpsTracker] start() called")

    // 리스너가 준비될 때까지 대기
    if (!this.isListenersReady) {
      console.warn("[RidableGpsTracker] ⚠️ Listeners not ready yet, waiting...")
      await new Promise((resolve) => setTimeout(resolve, 300))
    }

    console.log("[RidableGpsTracker] Starting GPS tracking...")
    return RidableGpsTrackerModule.start()
  }

  /**
   * Stop GPS tracking
   */
  async stop(): Promise<void> {
    return RidableGpsTrackerModule.stop()
  }

  /**
   * Get current location (last known location)
   */
  async getCurrentLocation(): Promise<LocationData> {
    return RidableGpsTrackerModule.getCurrentLocation()
  }

  /**
   * Check tracking status and permissions
   */
  async checkStatus(): Promise<LocationStatus> {
    return RidableGpsTrackerModule.checkStatus()
  }

  /**
   * Request location permissions
   */
  async requestPermissions(): Promise<boolean> {
    return RidableGpsTrackerModule.requestPermissions()
  }

  /**
   * Open device location settings
   */
  openLocationSettings(): void {
    RidableGpsTrackerModule.openLocationSettings()
  }

  /**
   * Add listener for location updates
   */
  addLocationListener(callback: LocationEventCallback): () => void {
    console.log("[RidableGpsTracker] addLocationListener() called")

    // JS 이벤트 리스너 등록 - 이것이 자동으로 startObserving을 트리거함
    this.locationListener = eventEmitter.addListener("location", callback)
    this.isListenersReady = true

    console.log("[RidableGpsTracker] ✅ Location listener registered")

    return () => {
      this.removeLocationListener()
    }
  }

  /**
   * Remove location listener
   */
  removeLocationListener(): void {
    if (this.locationListener) {
      this.locationListener.remove()
      this.locationListener = null

      // 모든 리스너가 제거되면 준비 플래그 해제
      if (!this.errorListener && !this.authListener) {
        this.isListenersReady = false
      }
      console.log("[RidableGpsTracker] Location listener removed")
    }
  }

  /**
   * Add listener for errors
   */
  addErrorListener(callback: (error: { code: number; message: string }) => void): () => void {
    console.log("[RidableGpsTracker] addErrorListener() called")

    this.errorListener = eventEmitter.addListener("error", callback)
    this.isListenersReady = true

    console.log("[RidableGpsTracker] ✅ Error listener registered")

    return () => {
      if (this.errorListener) {
        this.errorListener.remove()
        this.errorListener = null
        if (!this.locationListener && !this.authListener) {
          this.isListenersReady = false
        }
        console.log("[RidableGpsTracker] Error listener removed")
      }
    }
  }

  /**
   * Add listener for authorization changes
   */
  addAuthorizationListener(callback: (status: { status: string }) => void): () => void {
    console.log("[RidableGpsTracker] addAuthorizationListener() called")

    this.authListener = eventEmitter.addListener("authorizationChanged", callback)
    this.isListenersReady = true

    return () => {
      if (this.authListener) {
        this.authListener.remove()
        this.authListener = null
        if (!this.locationListener && !this.errorListener) {
          this.isListenersReady = false
        }
      }
    }
  }

  /**
   * Remove all listeners
   */
  removeAllListeners(): void {
    if (this.locationListener) {
      this.locationListener.remove()
      this.locationListener = null
    }
    if (this.errorListener) {
      this.errorListener.remove()
      this.errorListener = null
    }
    if (this.authListener) {
      this.authListener.remove()
      this.authListener = null
    }
    this.isListenersReady = false
  }
}

export default new RidableGpsTracker()
export * from "./types"
