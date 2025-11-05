import type { TurboModule } from "react-native"
import { TurboModuleRegistry } from "react-native"

export interface Spec extends TurboModule {
  // Configuration
  configure(config: Object): Promise<void>

  // Start/Stop tracking
  start(): Promise<void>
  stop(): Promise<void>

  // Get current location
  getCurrentLocation(): Promise<Object>

  // Check status
  checkStatus(): Promise<Object>

  // Request permissions
  requestPermissions(): Promise<boolean>

  // Open settings
  openLocationSettings(): void

  // Add event listener (handled by EventEmitter)
  addListener(eventName: string): void
  removeListeners(count: number): void
}

export default TurboModuleRegistry.getEnforcing<Spec>("RNRidableGpsTracker")
