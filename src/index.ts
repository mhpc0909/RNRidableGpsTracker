import { NativeEventEmitter, Platform } from 'react-native'
import NativeRidableGpsTracker from './NativeRidableGpsTracker'
import type {
  LocationConfig,
  LocationData,
  LocationStatus,
  LocationEventCallback,
} from './types'

const LINKING_ERROR =
  `The package 'react-native-ridable-gps-tracker' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- Run 'pod install'\n", default: '' }) +
  '- Rebuild the app after installing the package\n' +
  '- If using New Architecture, ensure Codegen has run\n'

// @ts-expect-error - NativeModule can be null
const isTurboModuleEnabled = global.__turboModuleProxy != null

const RidableGpsTrackerModule = isTurboModuleEnabled
  ? NativeRidableGpsTracker
  : require('./NativeRidableGpsTracker').default

if (!RidableGpsTrackerModule) {
  throw new Error(LINKING_ERROR)
}

// @ts-expect-error - EventEmitter type
const eventEmitter = new NativeEventEmitter(RidableGpsTrackerModule)

class RidableGpsTracker {
  private locationListener: any = null

  async configure(config: LocationConfig): Promise<void> {
    return RidableGpsTrackerModule.configure(config)
  }

  async start(): Promise<void> {
    return RidableGpsTrackerModule.start()
  }

  async stop(): Promise<void> {
    return RidableGpsTrackerModule.stop()
  }

  async getCurrentLocation(): Promise<LocationData> {
    return RidableGpsTrackerModule.getCurrentLocation()
  }

  async checkStatus(): Promise<LocationStatus> {
    return RidableGpsTrackerModule.checkStatus()
  }

  async requestPermissions(): Promise<boolean> {
    return RidableGpsTrackerModule.requestPermissions()
  }

  openLocationSettings(): void {
    RidableGpsTrackerModule.openLocationSettings()
  }

  addLocationListener(callback: LocationEventCallback): () => void {
    this.locationListener = eventEmitter.addListener('location', callback)
    RidableGpsTrackerModule.addListener('location')
    
    return () => {
      this.removeLocationListener()
    }
  }

  removeLocationListener(): void {
    if (this.locationListener) {
      this.locationListener.remove()
      this.locationListener = null
      RidableGpsTrackerModule.removeListeners(1)
    }
  }
}

export default new RidableGpsTracker()
export * from './types'
