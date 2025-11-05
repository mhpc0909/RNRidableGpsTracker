# react-native-ridable-gps-tracker

High-performance GPS tracking module for cycling apps, built with React Native Turbo Module architecture.

## Features

- 🚀 Turbo Native Module architecture for maximum performance
- 📍 Accurate GPS tracking optimized for cycling
- 🔋 Battery-efficient location updates
- 📱 iOS and Android support
- 🎯 Simple and clean API
- ⚡ Background location tracking support

## Installation

```bash
npm install react-native-ridable-gps-tracker
# or
yarn add react-native-ridable-gps-tracker
```

### iOS

```bash
cd ios && pod install
```

Add the following to your `Info.plist`:

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>We need your location to track your rides</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>We need your location to track your rides even when the app is in the background</string>
<key>UIBackgroundModes</key>
<array>
    <string>location</string>
</array>
```

### Android

Add the following to your `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_BACKGROUND_LOCATION" />
```

## Usage

```typescript
import GpsTracker, { LocationEvent } from 'react-native-ridable-gps-tracker';

// Configure GPS tracker
await GpsTracker.configure({
  distanceFilter: 10, // meters
  desiredAccuracy: 'high',
  activityType: 'fitness',
  allowsBackgroundLocationUpdates: true,
  interval: 1000, // Android only, milliseconds
  fastestInterval: 500, // Android only, milliseconds
});

// Request permissions
const granted = await GpsTracker.requestPermissions();

if (granted) {
  // Start tracking
  await GpsTracker.start();

  // Listen to location updates
  const subscription = GpsTracker.addListener(
    LocationEvent.LOCATION,
    (location) => {
      console.log('Location:', location);
      // {
      //   latitude: 37.7749,
      //   longitude: -122.4194,
      //   altitude: 50,
      //   accuracy: 10,
      //   speed: 5.5,
      //   bearing: 90,
      //   timestamp: 1234567890000
      // }
    }
  );

  // Get current location (one-time)
  const location = await GpsTracker.getCurrentLocation();

  // Check status
  const status = await GpsTracker.checkStatus();
  console.log('Status:', status);
  // {
  //   isRunning: true,
  //   isAuthorized: true,
  //   authorizationStatus: 'authorizedAlways'
  // }

  // Stop tracking
  await GpsTracker.stop();

  // Clean up
  subscription.remove();
}
```

## API

### Methods

#### `configure(config: GpsConfig): Promise<void>`

Configure the GPS tracker with desired settings.

**Config options:**
- `distanceFilter` (number): Minimum distance in meters before location update (default: 10)
- `desiredAccuracy` ('high' | 'medium' | 'low'): Accuracy level (default: 'high')
- `activityType` ('fitness' | 'automotiveNavigation' | 'otherNavigation' | 'other'): iOS only (default: 'fitness')
- `allowsBackgroundLocationUpdates` (boolean): Enable background updates (default: true)
- `showsBackgroundLocationIndicator` (boolean): iOS only (default: true)
- `pausesLocationUpdatesAutomatically` (boolean): iOS only (default: false)
- `interval` (number): Android only, update interval in ms (default: 1000)
- `fastestInterval` (number): Android only, fastest interval in ms (default: 500)

#### `start(): Promise<void>`

Start GPS tracking.

#### `stop(): Promise<void>`

Stop GPS tracking.

#### `getCurrentLocation(): Promise<LocationData>`

Get current location (one-time request).

#### `checkStatus(): Promise<GpsStatus>`

Check GPS tracker status.

#### `requestPermissions(): Promise<boolean>`

Request location permissions.

#### `openLocationSettings(): void`

Open device location settings.

#### `addListener(event: LocationEvent, callback: Function): Subscription`

Add event listener. Returns a subscription object with a `remove()` method.

**Events:**
- `LocationEvent.LOCATION`: Location updates
- `LocationEvent.ERROR`: Location errors
- `LocationEvent.AUTHORIZATION_CHANGED`: Authorization status changes

#### `removeAllListeners(event?: LocationEvent): void`

Remove all listeners for a specific event or all events.

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

## Example

See the example app in the `example` directory for a complete implementation.

## Performance Tips

1. **Distance Filter**: Set appropriate `distanceFilter` to reduce unnecessary updates
2. **Accuracy**: Use 'medium' or 'low' accuracy if high precision is not required
3. **Battery**: Lower accuracy and higher distance filters save battery
4. **Background**: Only enable background updates when necessary

## License

MIT

## Author

Mike
