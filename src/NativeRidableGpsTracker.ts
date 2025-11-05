import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';
import type { GpsConfig, LocationData, GpsStatus } from './types';

export interface Spec extends TurboModule {
  // Configuration
  configure(config: GpsConfig): Promise<void>;
  
  // Start/Stop tracking
  start(): Promise<void>;
  stop(): Promise<void>;
  
  // Get current location
  getCurrentLocation(): Promise<LocationData>;
  
  // Check status
  checkStatus(): Promise<GpsStatus>;
  
  // Request permissions
  requestPermissions(): Promise<boolean>;
  
  // Open settings
  openLocationSettings(): void;
  
  // Add event listener (handled by EventEmitter)
  addListener(eventName: string): void;
  removeListeners(count: number): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('RNRidableGpsTracker');
