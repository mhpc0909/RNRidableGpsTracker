import UIKit
import CoreLocation

class ViewController: UIViewController, CLLocationManagerDelegate {
    
    private let locationManager = CLLocationManager()
    private var isTracking = false
    private var locationHistory: [String] = []
    private var repeatLocationTimer: Timer?
    
    // UI Elements
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    
    private let statusCard = UIView()
    private let statusLabel = UILabel()
    
    private let controlsCard = UIView()
    private let requestPermButton = UIButton(type: .system)
    private let startButton = UIButton(type: .system)
    private let stopButton = UIButton(type: .system)
    private let getCurrentButton = UIButton(type: .system)
    
    private let locationCard = UIView()
    private let locationLabel = UILabel()
    
    private let historyCard = UIView()
    private let historyLabel = UILabel()
    private let clearButton = UIButton(type: .system)
    private let historyScrollView = UIScrollView()
    private let historyTextLabel = UILabel()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor(red: 0.96, green: 0.96, blue: 0.96, alpha: 1.0)
        
        setupScrollView()
        setupViews()
        setupConstraints()
        setupLocationManager()
        updateStatus()
    }
    
    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            
            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }
    
    private func setupViews() {
        // Title
        titleLabel.text = "GPS Tracker Example"
        titleLabel.font = UIFont.boldSystemFont(ofSize: 24)
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)
        
        subtitleLabel.text = "RNRidable GPS Tracker - Native iOS"
        subtitleLabel.font = UIFont.systemFont(ofSize: 14)
        subtitleLabel.textColor = .gray
        subtitleLabel.textAlignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(subtitleLabel)
        
        // Status Card
        setupCard(statusCard)
        contentView.addSubview(statusCard)
        
        statusLabel.text = "📍 Status\n\nLoading..."
        statusLabel.font = UIFont.systemFont(ofSize: 14)
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusCard.addSubview(statusLabel)
        
        // Controls Card
        setupCard(controlsCard)
        contentView.addSubview(controlsCard)
        
        setupButton(requestPermButton, title: "Request Permissions", color: .systemBlue)
        requestPermButton.addTarget(self, action: #selector(requestPermissions), for: .touchUpInside)
        
        setupButton(startButton, title: "Start Tracking", color: .systemGreen)
        startButton.addTarget(self, action: #selector(startTracking), for: .touchUpInside)
        
        setupButton(stopButton, title: "Stop Tracking", color: .systemRed)
        stopButton.addTarget(self, action: #selector(stopTracking), for: .touchUpInside)
        
        setupButton(getCurrentButton, title: "Get Current Location", color: .systemBlue)
        getCurrentButton.addTarget(self, action: #selector(getCurrentLocation), for: .touchUpInside)
        
        controlsCard.addSubview(requestPermButton)
        controlsCard.addSubview(startButton)
        controlsCard.addSubview(stopButton)
        controlsCard.addSubview(getCurrentButton)
        
        // Location Card
        setupCard(locationCard)
        contentView.addSubview(locationCard)
        
        locationLabel.text = "📌 Current Location\n\nNo location data"
        locationLabel.font = UIFont.systemFont(ofSize: 14)
        locationLabel.numberOfLines = 0
        locationLabel.translatesAutoresizingMaskIntoConstraints = false
        locationCard.addSubview(locationLabel)
        
        // History Card
        setupCard(historyCard)
        contentView.addSubview(historyCard)
        
        historyLabel.text = "Location History"
        historyLabel.font = UIFont.boldSystemFont(ofSize: 18)
        historyLabel.translatesAutoresizingMaskIntoConstraints = false
        historyCard.addSubview(historyLabel)
        
        clearButton.setTitle("Clear", for: .normal)
        clearButton.setTitleColor(.white, for: .normal)
        clearButton.backgroundColor = .systemRed
        clearButton.layer.cornerRadius = 8
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.addTarget(self, action: #selector(clearHistory), for: .touchUpInside)
        historyCard.addSubview(clearButton)
        
        historyScrollView.layer.cornerRadius = 8
        historyScrollView.backgroundColor = UIColor(white: 0.95, alpha: 1)
        historyScrollView.translatesAutoresizingMaskIntoConstraints = false
        historyCard.addSubview(historyScrollView)
        
        historyTextLabel.text = "📜 Location History (0)\n\n"
        historyTextLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        historyTextLabel.numberOfLines = 0
        historyTextLabel.translatesAutoresizingMaskIntoConstraints = false
        historyScrollView.addSubview(historyTextLabel)
    }
    
    private func setupCard(_ card: UIView) {
        card.backgroundColor = .white
        card.layer.cornerRadius = 12
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOffset = CGSize(width: 0, height: 2)
        card.layer.shadowOpacity = 0.1
        card.layer.shadowRadius = 4
        card.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupButton(_ button: UIButton, title: String, color: UIColor) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = color
        button.layer.cornerRadius = 8
        button.translatesAutoresizingMaskIntoConstraints = false
    }
    
    private func setupConstraints() {
        let padding: CGFloat = 16
        
        NSLayoutConstraint.activate([
            // Title
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: padding),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            subtitleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            
            // Status Card
            statusCard.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 24),
            statusCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            statusCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            
            statusLabel.topAnchor.constraint(equalTo: statusCard.topAnchor, constant: padding),
            statusLabel.leadingAnchor.constraint(equalTo: statusCard.leadingAnchor, constant: padding),
            statusLabel.trailingAnchor.constraint(equalTo: statusCard.trailingAnchor, constant: -padding),
            statusLabel.bottomAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: -padding),
            
            // Controls Card
            controlsCard.topAnchor.constraint(equalTo: statusCard.bottomAnchor, constant: padding),
            controlsCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            controlsCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            
            requestPermButton.topAnchor.constraint(equalTo: controlsCard.topAnchor, constant: padding),
            requestPermButton.leadingAnchor.constraint(equalTo: controlsCard.leadingAnchor, constant: padding),
            requestPermButton.trailingAnchor.constraint(equalTo: controlsCard.trailingAnchor, constant: -padding),
            requestPermButton.heightAnchor.constraint(equalToConstant: 44),
            
            startButton.topAnchor.constraint(equalTo: requestPermButton.bottomAnchor, constant: 12),
            startButton.leadingAnchor.constraint(equalTo: controlsCard.leadingAnchor, constant: padding),
            startButton.trailingAnchor.constraint(equalTo: controlsCard.centerXAnchor, constant: -6),
            startButton.heightAnchor.constraint(equalToConstant: 44),
            
            stopButton.topAnchor.constraint(equalTo: requestPermButton.bottomAnchor, constant: 12),
            stopButton.leadingAnchor.constraint(equalTo: controlsCard.centerXAnchor, constant: 6),
            stopButton.trailingAnchor.constraint(equalTo: controlsCard.trailingAnchor, constant: -padding),
            stopButton.heightAnchor.constraint(equalToConstant: 44),
            
            getCurrentButton.topAnchor.constraint(equalTo: startButton.bottomAnchor, constant: 12),
            getCurrentButton.leadingAnchor.constraint(equalTo: controlsCard.leadingAnchor, constant: padding),
            getCurrentButton.trailingAnchor.constraint(equalTo: controlsCard.trailingAnchor, constant: -padding),
            getCurrentButton.heightAnchor.constraint(equalToConstant: 44),
            getCurrentButton.bottomAnchor.constraint(equalTo: controlsCard.bottomAnchor, constant: -padding),
            
            // Location Card
            locationCard.topAnchor.constraint(equalTo: controlsCard.bottomAnchor, constant: padding),
            locationCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            locationCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            
            locationLabel.topAnchor.constraint(equalTo: locationCard.topAnchor, constant: padding),
            locationLabel.leadingAnchor.constraint(equalTo: locationCard.leadingAnchor, constant: padding),
            locationLabel.trailingAnchor.constraint(equalTo: locationCard.trailingAnchor, constant: -padding),
            locationLabel.bottomAnchor.constraint(equalTo: locationCard.bottomAnchor, constant: -padding),
            
            // History Card
            historyCard.topAnchor.constraint(equalTo: locationCard.bottomAnchor, constant: padding),
            historyCard.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            historyCard.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            historyCard.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -padding),
            
            historyLabel.topAnchor.constraint(equalTo: historyCard.topAnchor, constant: padding),
            historyLabel.leadingAnchor.constraint(equalTo: historyCard.leadingAnchor, constant: padding),
            
            clearButton.centerYAnchor.constraint(equalTo: historyLabel.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: historyCard.trailingAnchor, constant: -padding),
            clearButton.widthAnchor.constraint(equalToConstant: 60),
            clearButton.heightAnchor.constraint(equalToConstant: 32),
            
            historyScrollView.topAnchor.constraint(equalTo: historyLabel.bottomAnchor, constant: 12),
            historyScrollView.leadingAnchor.constraint(equalTo: historyCard.leadingAnchor, constant: padding),
            historyScrollView.trailingAnchor.constraint(equalTo: historyCard.trailingAnchor, constant: -padding),
            historyScrollView.heightAnchor.constraint(equalToConstant: 300),
            historyScrollView.bottomAnchor.constraint(equalTo: historyCard.bottomAnchor, constant: -padding),
            
            historyTextLabel.topAnchor.constraint(equalTo: historyScrollView.topAnchor, constant: 8),
            historyTextLabel.leadingAnchor.constraint(equalTo: historyScrollView.leadingAnchor, constant: 8),
            historyTextLabel.trailingAnchor.constraint(equalTo: historyScrollView.trailingAnchor, constant: -8),
            historyTextLabel.bottomAnchor.constraint(equalTo: historyScrollView.bottomAnchor, constant: -8),
            historyTextLabel.widthAnchor.constraint(equalTo: historyScrollView.widthAnchor, constant: -16)
        ])
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationManager.activityType = .otherNavigation
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.allowsBackgroundLocationUpdates = true
        if #available(iOS 11.0, *) {
            locationManager.showsBackgroundLocationIndicator = true
        }
    }
    
    private func updateStatus() {
        let authStatus = locationManager.authorizationStatus
        var statusText = "📍 Status\n\n"
        statusText += "Tracking: \(isTracking ? "✅ Running" : "❌ Stopped")\n"
        
        switch authStatus {
        case .authorizedAlways:
            statusText += "Permission: ✅ Granted (Always)\n"
        case .authorizedWhenInUse:
            statusText += "Permission: ✅ Granted (When In Use)\n"
        case .denied:
            statusText += "Permission: ❌ Denied\n"
        case .restricted:
            statusText += "Permission: ❌ Restricted\n"
        case .notDetermined:
            statusText += "Permission: ⚠️ Not Determined\n"
        @unknown default:
            statusText += "Permission: ❓ Unknown\n"
        }
        
        statusLabel.text = statusText
        
        startButton.isEnabled = (authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse) && !isTracking
        stopButton.isEnabled = isTracking
        getCurrentButton.isEnabled = (authStatus == .authorizedAlways || authStatus == .authorizedWhenInUse)
    }
    
    @objc private func requestPermissions() {
        locationManager.requestAlwaysAuthorization()
    }
    
    @objc private func startTracking() {
        locationManager.startUpdatingLocation()
        isTracking = true
        startRepeatLocationUpdates()
        updateStatus()
        showAlert(title: "Success", message: "GPS 트래킹 시작")
    }
    
    @objc private func stopTracking() {
        locationManager.stopUpdatingLocation()
        isTracking = false
        stopRepeatLocationUpdates()
        updateStatus()
        showAlert(title: "Success", message: "GPS 트래킹 중지")
    }
    
    @objc private func getCurrentLocation() {
        locationManager.requestLocation()
    }
    
    @objc private func clearHistory() {
        locationHistory.removeAll()
        updateHistoryDisplay()
    }
    
    private func updateLocationDisplay(_ location: CLLocation) {
        var text = "📌 Current Location\n\n"
        text += "Latitude: \(String(format: "%.6f", location.coordinate.latitude))\n"
        text += "Longitude: \(String(format: "%.6f", location.coordinate.longitude))\n"
        text += "Altitude: \(String(format: "%.1f", location.altitude))m\n"
        text += "Accuracy: \(String(format: "%.1f", location.horizontalAccuracy))m\n"
        text += "Speed: \(String(format: "%.1f", location.speed >= 0 ? location.speed : 0)) m/s\n"
        text += "Bearing: \(String(format: "%.1f", location.course >= 0 ? location.course : 0))°\n"
        
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        text += "Time: \(formatter.string(from: location.timestamp))\n"
        
        locationLabel.text = text
    }
    
    private func addToHistory(_ location: CLLocation) {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        let time = formatter.string(from: location.timestamp)
        
        let entry = "\(locationHistory.count + 1). (\(String(format: "%.4f", location.coordinate.latitude)), " +
            "\(String(format: "%.4f", location.coordinate.longitude))) - " +
            "\(String(format: "%.1f", location.speed >= 0 ? location.speed : 0)) m/s - \(time)"
        
        locationHistory.insert(entry, at: 0)
        if locationHistory.count > 50 {
            locationHistory.removeLast()
        }
        
        updateHistoryDisplay()
    }
    
    private func updateHistoryDisplay() {
        var text = "📜 Location History (\(locationHistory.count))\n\n"
        text += locationHistory.joined(separator: "\n")
        historyTextLabel.text = text
        
        DispatchQueue.main.async {
            self.historyScrollView.setContentOffset(.zero, animated: true)
        }
    }
    
    private func showAlert(title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        updateLocationDisplay(location)
        if isTracking {
            addToHistory(location)
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        showAlert(title: "Error", message: "Failed to get location: \(error.localizedDescription)")
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateStatus()
    }
    
    // MARK: - Repeat Location Updates
    
    private func startRepeatLocationUpdates() {
        stopRepeatLocationUpdates()
        
        print("[GPS Tracker] Starting repeat location updates (1 second interval)")
        
        repeatLocationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.repeatLocationUpdate()
        }
    }
    
    private func stopRepeatLocationUpdates() {
        repeatLocationTimer?.invalidate()
        repeatLocationTimer = nil
        print("[GPS Tracker] Stopped repeat location updates")
    }
    
    private func repeatLocationUpdate() {
        // 마지막 위치를 가져와서 업데이트
        if let lastLocation = locationManager.location, isTracking {
            print("[GPS Tracker] Repeating last location (for 1-second interval)")
            updateLocationDisplay(lastLocation)
            addToHistory(lastLocation)
        }
    }
}
