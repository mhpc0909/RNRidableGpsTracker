export interface LocationData {
  latitude: number;
  longitude: number;
  altitude: number;
  accuracy: number;
  speed: number;
  bearing: number;
  timestamp: number;
}

export interface GpsConfig {
  // Distance filter in meters
  distanceFilter: number;
  // Desired accuracy in meters
  desiredAccuracy: 'high' | 'medium' | 'low';
  // Update interval in milliseconds (Android)
  interval?: number;
  // Fastest update interval in milliseconds (Android)
  fastestInterval?: number;
  // Activity type for iOS
  activityType?: 'fitness' | 'automotiveNavigation' | 'otherNavigation' | 'other';
  // Enable background location updates
  allowsBackgroundLocationUpdates?: boolean;
  // Show background location indicator (iOS 11+)
  showsBackgroundLocationIndicator?: boolean;
  // Pause updates automatically (iOS)
  pausesLocationUpdatesAutomatically?: boolean;
}

export interface GpsStatus {
  isRunning: boolean;
  isAuthorized: boolean;
  authorizationStatus: 'notDetermined' | 'restricted' | 'denied' | 'authorizedAlways' | 'authorizedWhenInUse';
}

export enum LocationEvent {
  LOCATION = 'location',
  ERROR = 'error',
  AUTHORIZATION_CHANGED = 'authorizationChanged',
}

export enum AuthorizationStatus {
  NOT_DETERMINED = 0,
  RESTRICTED = 1,
  DENIED = 2,
  AUTHORIZED_ALWAYS = 3,
  AUTHORIZED_WHEN_IN_USE = 4,
}

export enum AccuracyLevel {
  HIGH = 0,
  MEDIUM = 1,
  LOW = 2,
}
