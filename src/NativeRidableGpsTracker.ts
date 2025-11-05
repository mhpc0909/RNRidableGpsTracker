import type { TurboModule } from 'react-native'
import { TurboModuleRegistry } from 'react-native'

export interface Spec extends TurboModule {
  configure(config: Object): Promise<void>
  start(): Promise<void>
  stop(): Promise<void>
  getCurrentLocation(): Promise<Object>
  checkStatus(): Promise<Object>
  requestPermissions(): Promise<boolean>
  openLocationSettings(): void
  addListener(eventName: string): void
  removeListeners(count: number): void
}

export default TurboModuleRegistry.getEnforcing<Spec>('RNRidableGpsTracker')
