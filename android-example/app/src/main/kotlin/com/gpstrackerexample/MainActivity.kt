package com.gpstrackerexample

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import android.widget.Button
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat
import com.google.android.gms.location.*

class MainActivity : AppCompatActivity() {

    private lateinit var statusText: TextView
    private lateinit var locationText: TextView
    private lateinit var historyText: TextView
    private lateinit var historyScrollView: ScrollView
    private lateinit var startButton: Button
    private lateinit var stopButton: Button
    private lateinit var getCurrentButton: Button
    private lateinit var requestPermButton: Button

    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var isTracking = false
    private val locationHistory = mutableListOf<String>()
    
    private var locationService: LocationService? = null
    private var isServiceBound = false

    companion object {
        private const val TAG = "MainActivity"
    }

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            Log.d(TAG, "Service connected")
            val binder = service as LocationService.LocalBinder
            locationService = binder.getService()
            isServiceBound = true
            
            // Configure the service
            locationService?.configure(
                distanceFilter = 0f,
                updateInterval = 1000L,
                fastestInterval = 1000L,
                desiredAccuracy = "high"
            )
            
            // Set location listener
            locationService?.setLocationListener { location ->
                updateLocationDisplay(location)
                if (isTracking) {
                    addToHistory(location)
                }
            }
            
            updateStatus()
            Toast.makeText(this@MainActivity, "✅ Service Connected!", Toast.LENGTH_SHORT).show()
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.d(TAG, "Service disconnected")
            locationService = null
            isServiceBound = false
            updateStatus()
        }
    }

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val fineLocation = permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true
        val coarseLocation = permissions[Manifest.permission.ACCESS_COARSE_LOCATION] == true
        
        if (fineLocation || coarseLocation) {
            Toast.makeText(this, "✅ 위치 권한이 허용되었습니다", Toast.LENGTH_SHORT).show()
            
            // Android 13+ 알림 권한 체크
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val notification = permissions[Manifest.permission.POST_NOTIFICATIONS] == true
                if (notification) {
                    Toast.makeText(this, "✅ 알림 권한이 허용되었습니다", Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(this, "⚠️ 알림 권한이 거부되었습니다. GPS 알림이 표시되지 않을 수 있습니다.", Toast.LENGTH_LONG).show()
                }
            }
            
            updateStatus()
        } else {
            Toast.makeText(this, "❌ 위치 권한이 거부되었습니다", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        initViews()
        setupFusedLocationClient()
        bindLocationService()
        updateStatus()
    }

    private fun bindLocationService() {
        val intent = Intent(this, LocationService::class.java)
        val bound = bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
        Log.d(TAG, "Binding to LocationService, result: $bound")
    }

    override fun onDestroy() {
        super.onDestroy()
        if (isServiceBound) {
            unbindService(serviceConnection)
            isServiceBound = false
        }
        if (isTracking) {
            stopTracking()
        }
    }

    private fun initViews() {
        statusText = findViewById(R.id.status_text)
        locationText = findViewById(R.id.location_text)
        historyText = findViewById(R.id.history_text)
        historyScrollView = findViewById(R.id.history_scroll)
        startButton = findViewById(R.id.start_button)
        stopButton = findViewById(R.id.stop_button)
        getCurrentButton = findViewById(R.id.get_current_button)
        requestPermButton = findViewById(R.id.request_perm_button)

        startButton.setOnClickListener { startTracking() }
        stopButton.setOnClickListener { stopTracking() }
        getCurrentButton.setOnClickListener { getCurrentLocation() }
        requestPermButton.setOnClickListener { requestLocationPermissions() }
        findViewById<Button>(R.id.clear_history_button).setOnClickListener { clearHistory() }
    }

    private fun setupFusedLocationClient() {
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
    }

    private fun updateStatus() {
        val hasPermission = checkPermissions()
        val hasNotificationPermission = checkNotificationPermission()
        val backgroundPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

        val statusBuilder = StringBuilder()
        statusBuilder.append("📍 Status (Standalone Example)\n\n")
        statusBuilder.append("Tracking: ${if (isTracking) "✅ Running" else "❌ Stopped"}\n")
        statusBuilder.append("Service Bound: ${if (isServiceBound) "✅ Yes" else "❌ No"}\n")
        statusBuilder.append("Location: ${if (hasPermission) "✅ Granted" else "❌ Denied"}\n")
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            statusBuilder.append("Notification: ${if (hasNotificationPermission) "✅ Granted" else "⚠️ Denied"}\n")
        }
        
        statusBuilder.append("Background: ${if (backgroundPermission) "✅ Granted" else "⚠️ Denied"}\n")

        statusText.text = statusBuilder.toString()

        startButton.isEnabled = hasPermission && !isTracking && isServiceBound
        stopButton.isEnabled = isTracking
        getCurrentButton.isEnabled = hasPermission
        
        Log.d(TAG, "updateStatus - hasPermission: $hasPermission, isTracking: $isTracking, isServiceBound: $isServiceBound, startButton.isEnabled: ${startButton.isEnabled}")
    }

    private fun checkPermissions(): Boolean {
        val fineLocation = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        
        val coarseLocation = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
        
        return fineLocation || coarseLocation
    }

    private fun checkNotificationPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true // Android 13 미만은 알림 권한 불필요
        }
    }

    private fun requestLocationPermissions() {
        Log.d(TAG, "requestLocationPermissions called")
        
        val permissions = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        )

        // Android 10+ (API 29+): Background location
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            permissions.add(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        }

        // Android 13+ (API 33+): Notification permission
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        Log.d(TAG, "Requesting permissions: $permissions")
        requestPermissionLauncher.launch(permissions.toTypedArray())
    }

    private fun startTracking() {
        Log.d(TAG, "=== startTracking called ===")
        Log.d(TAG, "checkPermissions: ${checkPermissions()}")
        Log.d(TAG, "isServiceBound: $isServiceBound")
        Log.d(TAG, "locationService: $locationService")
        
        if (!checkPermissions()) {
            Log.w(TAG, "No location permission")
            Toast.makeText(this, "⚠️ 위치 권한이 필요합니다", Toast.LENGTH_SHORT).show()
            return
        }

        if (!isServiceBound || locationService == null) {
            Log.w(TAG, "Service not bound")
            Toast.makeText(this, "⚠️ 서비스가 연결되지 않았습니다. 잠시 후 다시 시도해주세요.", Toast.LENGTH_SHORT).show()
            return
        }

        // Android 13+ 알림 권한 체크
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !checkNotificationPermission()) {
            Toast.makeText(this, "⚠️ 알림 권한이 필요합니다. GPS 트래킹 알림이 표시되지 않습니다.", Toast.LENGTH_LONG).show()
            // 알림 권한이 없어도 계속 진행 (서비스는 동작하지만 알림은 안 보임)
        }

        try {
            val serviceIntent = Intent(this, LocationService::class.java).apply {
                action = LocationService.ACTION_START
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(serviceIntent)
                Log.d(TAG, "startForegroundService called")
            } else {
                startService(serviceIntent)
                Log.d(TAG, "startService called")
            }

            locationService?.startForegroundTracking()
            Log.d(TAG, "startForegroundTracking called on service")
            
            isTracking = true
            updateStatus()
            Toast.makeText(this, "🚴 GPS 트래킹 시작", Toast.LENGTH_SHORT).show()
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception", e)
            Toast.makeText(this, "❌ 권한 오류: ${e.message}", Toast.LENGTH_LONG).show()
        } catch (e: Exception) {
            Log.e(TAG, "Exception while starting tracking", e)
            Toast.makeText(this, "❌ 오류: ${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    private fun stopTracking() {
        Log.d(TAG, "=== stopTracking called ===")
        
        if (isServiceBound && locationService != null) {
            Log.d(TAG, "Calling stopForegroundTracking on bound service")
            locationService?.stopForegroundTracking()
        }
        
        val serviceIntent = Intent(this, LocationService::class.java).apply {
            action = LocationService.ACTION_STOP
        }
        stopService(serviceIntent)
        Log.d(TAG, "stopService intent sent")
        
        isTracking = false
        updateStatus()
        Toast.makeText(this, "⏹️ GPS 트래킹 중지", Toast.LENGTH_SHORT).show()
    }

    private fun getCurrentLocation() {
        Log.d(TAG, "getCurrentLocation called")
        
        if (!checkPermissions()) {
            Toast.makeText(this, "⚠️ 위치 권한이 필요합니다", Toast.LENGTH_SHORT).show()
            return
        }

        try {
            val serviceLocation = locationService?.getLastLocation()
            if (serviceLocation != null) {
                updateLocationDisplay(serviceLocation)
                Toast.makeText(this, "✅ 현재 위치 조회 완료 (from service)", Toast.LENGTH_SHORT).show()
                return
            }

            fusedLocationClient?.lastLocation?.addOnSuccessListener { location ->
                if (location != null) {
                    updateLocationDisplay(location)
                    Toast.makeText(this, "✅ 현재 위치 조회 완료", Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(this, "⚠️ 위치를 가져올 수 없습니다. GPS를 켜주세요.", Toast.LENGTH_SHORT).show()
                }
            }
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception in getCurrentLocation", e)
            Toast.makeText(this, "❌ 권한 오류: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun updateLocationDisplay(location: Location) {
        val locBuilder = StringBuilder()
        locBuilder.append("📌 Current Location\n\n")
        locBuilder.append("Latitude: ${String.format("%.6f", location.latitude)}\n")
        locBuilder.append("Longitude: ${String.format("%.6f", location.longitude)}\n")
        locBuilder.append("Altitude: ${String.format("%.1f", location.altitude)}m\n")
        locBuilder.append("Accuracy: ${String.format("%.1f", location.accuracy)}m\n")
        locBuilder.append("Speed: ${String.format("%.1f", if (location.hasSpeed()) location.speed else 0f)} m/s\n")
        locBuilder.append("  (${String.format("%.1f", if (location.hasSpeed()) location.speed * 3.6 else 0f)} km/h)\n")
        locBuilder.append("Bearing: ${String.format("%.1f", if (location.hasBearing()) location.bearing else 0f)}°\n")
        locBuilder.append("Time: ${java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(location.time)}\n")

        locationText.text = locBuilder.toString()
    }

    private fun addToHistory(location: Location) {
        val time = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(location.time)
        val speedKmh = if (location.hasSpeed()) location.speed * 3.6 else 0f
        val entry = "${locationHistory.size + 1}. (${String.format("%.4f", location.latitude)}, " +
                "${String.format("%.4f", location.longitude)}) - " +
                "${String.format("%.1f", speedKmh)} km/h - $time"
        
        locationHistory.add(0, entry)
        if (locationHistory.size > 50) {
            locationHistory.removeLast()
        }

        updateHistoryDisplay()
    }

    private fun updateHistoryDisplay() {
        historyText.text = "📜 Location History (${locationHistory.size})\n\n" + 
            locationHistory.joinToString("\n")
        
        historyScrollView.post {
            historyScrollView.scrollTo(0, 0)
        }
    }

    private fun clearHistory() {
        locationHistory.clear()
        historyText.text = "📜 Location History (0)\n\n"
        Toast.makeText(this, "🗑️ History cleared", Toast.LENGTH_SHORT).show()
    }
}
