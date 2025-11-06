export interface LocationData {
  latitude: number
  longitude: number
  altitude: number // GPS 기반 고도 (덜 정확)
  enhancedAltitude?: number // 🆕 GPS + 기압계 보정 고도 (더 정확)
  relativeAltitude?: number // 🆕 시작점 대비 상대 고도 변화
  pressure?: number // 🆕 기압 (kPa for iOS, hPa for Android)
  accuracy: number
  speed: number
  bearing: number
  timestamp: number
  isNewLocation: boolean // 🆕 새로운 GPS 데이터 여부 (true: 새 데이터, false: 반복 데이터)
}

export enum ExerciseType {
  BICYCLE = "bicycle", // 자전거
  RUNNING = "running", // 러닝
  HIKING = "hiking", // 하이킹
  WALKING = "walking", // 걷기
}

export interface LocationConfig {
  // Distance filter in meters
  distanceFilter?: number
  // Desired accuracy
  desiredAccuracy?: "high" | "medium" | "low"
  // Update interval in milliseconds (Android)
  interval?: number
  // Fastest update interval in milliseconds (Android)
  fastestInterval?: number
  // Activity type for iOS
  activityType?: "fitness" | "automotiveNavigation" | "otherNavigation" | "other"
  // Exercise type
  exerciseType?: ExerciseType
  // Enable background location updates
  allowsBackgroundLocationUpdates?: boolean
  // Show background location indicator (iOS 11+)
  showsBackgroundLocationIndicator?: boolean
  // Pause updates automatically (iOS)
  pausesLocationUpdatesAutomatically?: boolean
}

export interface LocationStatus {
  isRunning: boolean
  isAuthorized: boolean
  authorizationStatus: "notDetermined" | "restricted" | "denied" | "authorizedAlways" | "authorizedWhenInUse"
  isBarometerAvailable?: boolean // 🆕 기압계 센서 사용 가능 여부
}

export type LocationEventCallback = (location: LocationData) => void

export enum LocationEvent {
  LOCATION = "location",
  ERROR = "error",
  AUTHORIZATION_CHANGED = "authorizationChanged",
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

/**
 * 기압계 데이터 타입
 * - iOS: kPa (킬로파스칼) 단위
 * - Android: hPa (헥토파스칼) 단위
 *
 * 변환: 1 kPa = 10 hPa
 */
export interface BarometerData {
  pressure: number // 기압 (iOS: kPa, Android: hPa)
  relativeAltitude: number // 시작점 대비 상대 고도 (m)
  enhancedAltitude: number // GPS + 기압계 보정 고도 (m)
}

/**
 * 위치 데이터 사용 예시:
 *
 * tracker.addLocationListener((location) => {
 *   if (location.isNewLocation) {
 *     // ✅ 새로운 GPS 데이터 - DB에 저장
 *     console.log('🆕 NEW GPS data:', {
 *       lat: location.latitude,
 *       lng: location.longitude,
 *       altitude: location.altitude,              // GPS 고도
 *       enhancedAltitude: location.enhancedAltitude, // 기압계 보정 고도
 *       relativeAltitude: location.relativeAltitude, // 상대 고도 변화
 *       pressure: location.pressure                  // 기압
 *     });
 *
 *     // Realm에 저장
 *     saveToRealm(location);
 *   } else {
 *     // 🔄 반복 데이터 - UI 업데이트만
 *     console.log('🔄 Repeated location for UI update');
 *     updateMapMarker(location);
 *   }
 * });
 */
