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
    private var locationCallback: LocationCallback? = null
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
            
            // 서비스의 위치 업데이트 리스너 설정
            locationService?.setLocationListener { location ->
                updateLocationDisplay(location)
                if (isTracking) {
                    addToHistory(location)
                }
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.d(TAG, "Service disconnected")
            locationService = null
            isServiceBound = false
        }
    }

    private val requestPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { permissions ->
        val granted = permissions[Manifest.permission.ACCESS_FINE_LOCATION] == true
        if (granted) {
            Toast.makeText(this, "위치 권한이 허용되었습니다", Toast.LENGTH_SHORT).show()
            updateStatus()
        } else {
            Toast.makeText(this, "위치 권한이 거부되었습니다", Toast.LENGTH_SHORT).show()
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
        bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
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

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                locationResult.lastLocation?.let { location ->
                    updateLocationDisplay(location)
                    addToHistory(location)
                }
            }
        }
    }

    private fun updateStatus() {
        val hasPermission = checkPermissions()
        val backgroundPermission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_BACKGROUND_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }

        val statusBuilder = StringBuilder()
        statusBuilder.append("📍 Status\n\n")
        statusBuilder.append("Tracking: ${if (isTracking) "✅ Running" else "❌ Stopped"}\n")
        statusBuilder.append("Permission: ${if (hasPermission) "✅ Granted" else "❌ Denied"}\n")
        statusBuilder.append("Background: ${if (backgroundPermission) "✅ Granted" else "❌ Denied"}\n")

        statusText.text = statusBuilder.toString()

        startButton.isEnabled = hasPermission && !isTracking
        stopButton.isEnabled = isTracking
        getCurrentButton.isEnabled = hasPermission
    }

    private fun checkPermissions(): Boolean {
        return ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestLocationPermissions() {
        val permissions = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION
        )

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            permissions.add(Manifest.permission.ACCESS_BACKGROUND_LOCATION)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }

        requestPermissionLauncher.launch(permissions.toTypedArray())
    }

    private fun startTracking() {
        Log.d(TAG, "startTracking called")
        
        if (!checkPermissions()) {
            Toast.makeText(this, "위치 권한이 필요합니다", Toast.LENGTH_SHORT).show()
            return
        }

        try {
            // 포그라운드 서비스 시작
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

            // 서비스가 바인드되어 있으면 위치 리스너 설정
            if (isServiceBound && locationService != null) {
                locationService?.startForegroundTracking()
                locationService?.setLocationListener { location ->
                    updateLocationDisplay(location)
                    if (isTracking) {
                        addToHistory(location)
                    }
                }
                Log.d(TAG, "Location listener set")
            }

            isTracking = true
            updateStatus()
            Toast.makeText(this, "GPS 트래킹 시작", Toast.LENGTH_SHORT).show()
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception", e)
            Toast.makeText(this, "권한 오류: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    private fun stopTracking() {
        Log.d(TAG, "stopTracking called")
        
        // 바인드된 서비스를 통해 직접 중지
        if (isServiceBound && locationService != null) {
            Log.d(TAG, "Calling stopForegroundTracking on bound service")
            locationService?.stopForegroundTracking()
        }
        
        // 서비스 중지 Intent 전송 (추가 안전장치)
        val serviceIntent = Intent(this, LocationService::class.java).apply {
            action = LocationService.ACTION_STOP
        }
        stopService(serviceIntent)
        Log.d(TAG, "stopService intent sent")
        
        // 기존 위치 업데이트도 제거 (안전을 위해)
        locationCallback?.let {
            fusedLocationClient?.removeLocationUpdates(it)
        }
        
        isTracking = false
        updateStatus()
        Toast.makeText(this, "GPS 트래킹 중지", Toast.LENGTH_SHORT).show()
        Log.d(TAG, "stopTracking completed")
    }

    private fun getCurrentLocation() {
        if (!checkPermissions()) {
            Toast.makeText(this, "위치 권한이 필요합니다", Toast.LENGTH_SHORT).show()
            return
        }

        try {
            fusedLocationClient?.lastLocation?.addOnSuccessListener { location ->
                if (location != null) {
                    updateLocationDisplay(location)
                    Toast.makeText(this, "현재 위치 조회 완료", Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(this, "위치를 가져올 수 없습니다", Toast.LENGTH_SHORT).show()
                }
            }
        } catch (e: SecurityException) {
            Toast.makeText(this, "권한 오류: ${e.message}", Toast.LENGTH_SHORT).show()
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
        locBuilder.append("Bearing: ${String.format("%.1f", if (location.hasBearing()) location.bearing else 0f)}°\n")
        locBuilder.append("Time: ${java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(location.time)}\n")

        locationText.text = locBuilder.toString()
    }

    private fun addToHistory(location: Location) {
        val time = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(location.time)
        val entry = "${locationHistory.size + 1}. (${String.format("%.4f", location.latitude)}, " +
                "${String.format("%.4f", location.longitude)}) - " +
                "${String.format("%.1f", if (location.hasSpeed()) location.speed else 0f)} m/s - $time"
        
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
    }
}
