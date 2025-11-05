# RNRidable GPS Tracker

High-performance GPS tracking module for React Native with Turbo Module architecture.

## 🎯 Features

- ✅ **Turbo Module** - New Architecture support
- ✅ **Foreground Service** - Reliable background tracking
- ✅ **Real-time Updates** - Event-based location streaming
- ✅ **Configurable** - Distance filter, accuracy, update intervals
- ✅ **Permission Handling** - Built-in permission requests
- ✅ **Battery Optimized** - Smart location updates

## 📦 Installation

```bash
npm install react-native-ridable-gps-tracker
# or
yarn add react-native-ridable-gps-tracker
```

### iOS

```bash
cd ios && pod install
```

Add to your `Info.plist`:
```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to track your rides</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need your location to track your rides in the background</string>
```

### Android

Already configured! Just make sure you have Google Play Services in your app.

## 🚀 Usage

```typescript
import RidableGpsTracker, { LocationEvent } from 'react-native-ridable-gps-tracker';
import { NativeEventEmitter } from 'react-native';

// Create event emitter
const eventEmitter = new NativeEventEmitter(RidableGpsTracker);

// Configure GPS
await RidableGpsTracker.configure({
  distanceFilter: 10, // meters
  desiredAccuracy: 'high',
  interval: 1000, // Android only
  fastestInterval: 500, // Android only
  allowsBackgroundLocationUpdates: true, // iOS only
});

// Request permissions
const granted = await RidableGpsTracker.requestPermissions();

if (granted) {
  // Start tracking
  await RidableGpsTracker.start();
  
  // Listen to location updates
  const subscription = eventEmitter.addListener(
    LocationEvent.LOCATION,
    (location) => {
      console.log('New location:', location);
      // { latitude, longitude, altitude, speed, bearing, accuracy, timestamp }
    }
  );
  
  // Stop tracking
  await RidableGpsTracker.stop();
  
  // Clean up
  subscription.remove();
}
```

## 📖 API Reference

### Methods

#### `configure(config: GpsConfig): Promise<void>`
Configure GPS tracking parameters.

```typescript
interface GpsConfig {
  distanceFilter: number;              // Distance in meters
  desiredAccuracy: 'high' | 'medium' | 'low';
  interval?: number;                    // Android: update interval (ms)
  fastestInterval?: number;             // Android: fastest interval (ms)
  activityType?: 'fitness' | 'automotiveNavigation' | 'otherNavigation' | 'other'; // iOS
  allowsBackgroundLocationUpdates?: boolean;  // iOS
  showsBackgroundLocationIndicator?: boolean; // iOS
  pausesLocationUpdatesAutomatically?: boolean; // iOS
}
```

#### `start(): Promise<void>`
Start GPS tracking.

#### `stop(): Promise<void>`
Stop GPS tracking.

#### `getCurrentLocation(): Promise<LocationData>`
Get the last known location.

#### `checkStatus(): Promise<GpsStatus>`
Check GPS and permission status.

#### `requestPermissions(): Promise<boolean>`
Request location permissions.

#### `openLocationSettings(): void`
Open device location settings.

### Events

Listen to location events:

```typescript
import { LocationEvent } from 'react-native-ridable-gps-tracker';

// Location updates
eventEmitter.addListener(LocationEvent.LOCATION, (location) => {
  console.log(location);
});

// Errors
eventEmitter.addListener(LocationEvent.ERROR, (error) => {
  console.error(error);
});

// Authorization changes
eventEmitter.addListener(LocationEvent.AUTHORIZATION_CHANGED, (status) => {
  console.log('Auth status:', status);
});
```

### Types

```typescript
interface LocationData {
  latitude: number;
  longitude: number;
  altitude: number;
  accuracy: number;
  speed: number;
  bearing: number;
  timestamp: number;
}

interface GpsStatus {
  isRunning: boolean;
  isAuthorized: boolean;
  authorizationStatus: 'notDetermined' | 'restricted' | 'denied' | 'authorizedAlways' | 'authorizedWhenInUse';
}
```

## 🧪 Testing

### Android Example App

The `android-example` directory contains a native Android app that uses the module directly:

```bash
cd android-example
./gradlew installDebug
```

This demonstrates:
- ✅ Using the module from a native Android app
- ✅ Foreground service with notifications
- ✅ Real-time location updates
- ✅ Permission handling

## 🏗️ Architecture

```
┌─────────────────────────────────────┐
│  React Native (JavaScript)          │
│  RNRidableGpsTracker.start()        │
└──────────────┬──────────────────────┘
               │ Turbo Module Bridge
               ▼
┌─────────────────────────────────────┐
│  RNRidableGpsTrackerModule          │
│  (Kotlin/Objective-C++)             │
└──────────────┬──────────────────────┘
               │
               ▼
┌─────────────────────────────────────┐
│  LocationService                    │
│  (Foreground Service / CLLocationMgr)
└─────────────────────────────────────┘
```

## 📱 Permissions

### iOS
- `NSLocationWhenInUseUsageDescription`
- `NSLocationAlwaysAndWhenInUseUsageDescription`
- `UIBackgroundModes` - location

### Android
- `ACCESS_FINE_LOCATION`
- `ACCESS_COARSE_LOCATION`
- `ACCESS_BACKGROUND_LOCATION` (Android 10+)
- `FOREGROUND_SERVICE`
- `FOREGROUND_SERVICE_LOCATION` (Android 10+)
- `POST_NOTIFICATIONS` (Android 13+)

## 🔧 Troubleshooting

### Android: Service not starting
Make sure you have requested all required permissions including `FOREGROUND_SERVICE` and `POST_NOTIFICATIONS`.

### iOS: Location not updating in background
Enable background modes in Xcode:
1. Select your target
2. Signing & Capabilities
3. Add "Background Modes"
4. Check "Location updates"

### Module not found
Make sure you have:
1. Installed the module: `npm install`
2. Run pod install (iOS)
3. Rebuilt the app

## 📄 License

MIT

## 👤 Author

Mike - [KORA Project](https://github.com/yourusername)

## 🙏 Contributing

PRs welcome! This module is actively being developed for the KORA cycling app.
