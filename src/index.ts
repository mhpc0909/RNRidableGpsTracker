import { NativeEventEmitter, NativeModules, Platform } from 'react-native';
import type { LocationConfig, LocationData, LocationStatus, LocationEventCallback } from './types';

const LINKING_ERROR =
  `The package 'react-native-ridable-gps-tracker' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- Run 'pod install'\n", default: '' }) +
  '- Rebuild the app after installing the package\n';

const RidableGpsTrackerModule = NativeModules.RNRidableGpsTracker;

if (!RidableGpsTrackerModule) {
  throw new Error(LINKING_ERROR);
}

// Create event emitter
const eventEmitter = new NativeEventEmitter(RidableGpsTrackerModule);

class RidableGpsTracker {
  private locationListener: any = null;
  private errorListener: any = null;
  private authListener: any = null;

  /**
   * Configure GPS tracking settings
   */
  async configure(config: LocationConfig): Promise<void> {
    return RidableGpsTrackerModule.configure(config);
  }

  /**
   * Start GPS tracking
   */
  async start(): Promise<void> {
    return RidableGpsTrackerModule.start();
  }

  /**
   * Stop GPS tracking
   */
  async stop(): Promise<void> {
    return RidableGpsTrackerModule.stop();
  }

  /**
   * Get current location (last known location)
   */
  async getCurrentLocation(): Promise<LocationData> {
    return RidableGpsTrackerModule.getCurrentLocation();
  }

  /**
   * Check tracking status and permissions
   */
  async checkStatus(): Promise<LocationStatus> {
    return RidableGpsTrackerModule.checkStatus();
  }

  /**
   * Request location permissions
   */
  async requestPermissions(): Promise<boolean> {
    return RidableGpsTrackerModule.requestPermissions();
  }

  /**
   * Open device location settings
   */
  openLocationSettings(): void {
    RidableGpsTrackerModule.openLocationSettings();
  }

  /**
   * Add listener for location updates
   */
  addLocationListener(callback: LocationEventCallback): () => void {
    this.locationListener = eventEmitter.addListener('location', callback);
    RidableGpsTrackerModule.addListener('location');

    return () => {
      this.removeLocationListener();
    };
  }

  /**
   * Remove location listener
   */
  removeLocationListener(): void {
    if (this.locationListener) {
      this.locationListener.remove();
      this.locationListener = null;
      RidableGpsTrackerModule.removeListeners(1);
    }
  }

  /**
   * Add listener for errors
   */
  addErrorListener(callback: (error: { code: number; message: string }) => void): () => void {
    this.errorListener = eventEmitter.addListener('error', callback);
    RidableGpsTrackerModule.addListener('error');

    return () => {
      if (this.errorListener) {
        this.errorListener.remove();
        this.errorListener = null;
        RidableGpsTrackerModule.removeListeners(1);
      }
    };
  }

  /**
   * Add listener for authorization changes
   */
  addAuthorizationListener(callback: (status: { status: string }) => void): () => void {
    this.authListener = eventEmitter.addListener('authorizationChanged', callback);
    RidableGpsTrackerModule.addListener('authorizationChanged');

    return () => {
      if (this.authListener) {
        this.authListener.remove();
        this.authListener = null;
        RidableGpsTrackerModule.removeListeners(1);
      }
    };
  }

  /**
   * Remove all listeners
   */
  removeAllListeners(): void {
    this.removeLocationListener();
    if (this.errorListener) {
      this.errorListener.remove();
      this.errorListener = null;
    }
    if (this.authListener) {
      this.authListener.remove();
      this.authListener = null;
    }
    RidableGpsTrackerModule.removeListeners(3);
  }
}

export default new RidableGpsTracker();
export * from './types';
