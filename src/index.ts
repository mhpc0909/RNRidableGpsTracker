import { NativeEventEmitter, NativeModules, Platform } from 'react-native';
import NativeRidableGpsTracker from './NativeRidableGpsTracker';
import type { GpsConfig, LocationData, GpsStatus } from './types';
import { LocationEvent, AuthorizationStatus, AccuracyLevel } from './types';

const LINKING_ERROR =
  `The package 'react-native-ridable-gps-tracker' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- Run 'pod install'\n", default: '' }) +
  '- Rebuild the app after installing the package\n' +
  '- If you are using auto-linking, make sure it is enabled\n';

const RidableGpsTracker = NativeRidableGpsTracker
  ? NativeRidableGpsTracker
  : new Proxy(
      {},
      {
        get() {
          throw new Error(LINKING_ERROR);
        },
      }
    );

const eventEmitter = new NativeEventEmitter(
  NativeModules.RNRidableGpsTracker
);

// Event listener management
let listenerCount = 0;
const listeners = new Map<string, any>();

function addListener(
  eventType: LocationEvent,
  listener: (data: any) => void
) {
  const subscription = eventEmitter.addListener(eventType, listener);
  const key = `${eventType}_${listenerCount++}`;
  listeners.set(key, subscription);
  
  // Tell native module we have a listener
  RidableGpsTracker.addListener(eventType);
  
  return {
    remove: () => {
      subscription.remove();
      listeners.delete(key);
      RidableGpsTracker.removeListeners(1);
    },
  };
}

function removeAllListeners(eventType?: LocationEvent) {
  if (eventType) {
    listeners.forEach((subscription, key) => {
      if (key.startsWith(eventType)) {
        subscription.remove();
        listeners.delete(key);
      }
    });
    eventEmitter.removeAllListeners(eventType);
  } else {
    listeners.forEach((subscription) => {
      subscription.remove();
    });
    listeners.clear();
    eventEmitter.removeAllListeners();
  }
}

// Main API
export const GpsTracker = {
  /**
   * Configure the GPS tracker with desired settings
   */
  configure: (config: GpsConfig): Promise<void> => {
    return RidableGpsTracker.configure(config);
  },

  /**
   * Start GPS tracking
   */
  start: (): Promise<void> => {
    return RidableGpsTracker.start();
  },

  /**
   * Stop GPS tracking
   */
  stop: (): Promise<void> => {
    return RidableGpsTracker.stop();
  },

  /**
   * Get current location (one-time)
   */
  getCurrentLocation: (): Promise<LocationData> => {
    return RidableGpsTracker.getCurrentLocation();
  },

  /**
   * Check GPS tracker status
   */
  checkStatus: (): Promise<GpsStatus> => {
    return RidableGpsTracker.checkStatus();
  },

  /**
   * Request location permissions
   */
  requestPermissions: (): Promise<boolean> => {
    return RidableGpsTracker.requestPermissions();
  },

  /**
   * Open device location settings
   */
  openLocationSettings: (): void => {
    RidableGpsTracker.openLocationSettings();
  },

  /**
   * Add event listener
   */
  addListener,

  /**
   * Remove all listeners for an event type
   */
  removeAllListeners,

  // Constants
  Events: LocationEvent,
  AuthorizationStatus,
  AccuracyLevel,
};

// Export types
export * from './types';
export default GpsTracker;
