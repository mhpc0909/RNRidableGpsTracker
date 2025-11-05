import Foundation
import CoreLocation

@objc(RNRidableGpsTracker)
class RNRidableGpsTracker: RCTEventEmitter, CLLocationManagerDelegate {
    
    private var locationManager: CLLocationManager?
    private var lastLocation: CLLocation?
    private var isTracking = false
    
    // Configuration
    private var distanceFilter: CLLocationDistance = 0
    private var desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.allowsBackgroundLocationUpdates = true
        locationManager?.pausesLocationUpdatesAutomatically = false
        locationManager?.showsBackgroundLocationIndicator = true
    }
    
    override func supportedEvents() -> [String]! {
        return ["location"]
    }
    
    override static func requiresMainQueueSetup() -> Bool {
        return false
    }
    
    @objc
    func configure(_ config: NSDictionary, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        if let distance = config["distanceFilter"] as? Double {
            distanceFilter = distance
        }
        
        if let accuracy = config["desiredAccuracy"] as? String {
            switch accuracy {
            case "high":
                desiredAccuracy = kCLLocationAccuracyBest
            case "medium":
                desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            case "low":
                desiredAccuracy = kCLLocationAccuracyHundredMeters
            default:
                desiredAccuracy = kCLLocationAccuracyBest
            }
        }
        
        locationManager?.distanceFilter = distanceFilter
        locationManager?.desiredAccuracy = desiredAccuracy
        
        resolve(nil)
    }
    
    @objc
    func start(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        guard let locationManager = locationManager else {
            reject("NO_LOCATION_MANAGER", "Location manager not initialized", nil)
            return
        }
        
        let authStatus = CLLocationManager.authorizationStatus()
        if authStatus == .denied || authStatus == .restricted {
            reject("PERMISSION_DENIED", "Location permission denied", nil)
            return
        }
        
        isTracking = true
        locationManager.startUpdatingLocation()
        resolve(nil)
    }
    
    @objc
    func stop(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        isTracking = false
        locationManager?.stopUpdatingLocation()
        resolve(nil)
    }
    
    @objc
    func getCurrentLocation(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        if let location = lastLocation {
            resolve(convertLocationToDict(location))
        } else {
            reject("NO_LOCATION", "No location available", nil)
        }
    }
    
    @objc
    func checkStatus(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        let authStatus = CLLocationManager.authorizationStatus()
        
        var status: String
        switch authStatus {
        case .authorizedAlways:
            status = "authorizedAlways"
        case .authorizedWhenInUse:
            status = "authorizedWhenInUse"
        case .denied:
            status = "denied"
        case .restricted:
            status = "restricted"
        case .notDetermined:
            status = "notDetermined"
        @unknown default:
            status = "unknown"
        }
        
        let result: [String: Any] = [
            "isRunning": isTracking,
            "isAuthorized": authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse,
            "authorizationStatus": status
        ]
        
        resolve(result)
    }
    
    @objc
    func requestPermissions(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        locationManager?.requestAlwaysAuthorization()
        
        let authStatus = CLLocationManager.authorizationStatus()
        let isAuthorized = authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse
        resolve(isAuthorized)
    }
    
    @objc
    func openLocationSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
    }
    
    // CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        lastLocation = location
        
        if isTracking {
            sendEvent(withName: "location", body: convertLocationToDict(location))
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("Authorization status changed: \(status.rawValue)")
    }
    
    // Helper
    private func convertLocationToDict(_ location: CLLocation) -> [String: Any] {
        return [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "accuracy": location.horizontalAccuracy,
            "speed": location.speed >= 0 ? location.speed : 0,
            "bearing": location.course >= 0 ? location.course : 0,
            "timestamp": location.timestamp.timeIntervalSince1970 * 1000
        ]
    }
}
