package com.rnridablegpstracker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.location.Location
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*

class LocationService : Service() {

    private val binder = LocalBinder()
    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var lastLocation: Location? = null
    private var locationListener: ((Location) -> Unit)? = null
    private var isForegroundStarted = false
    
    // 1초마다 마지막 위치 전송용
    private val handler = Handler(Looper.getMainLooper())
    private var repeatLocationRunnable: Runnable? = null
    
    // Configuration
    private var distanceFilter: Float = 0f
    private var updateInterval: Long = 1000L
    private var fastestInterval: Long = 1000L
    private var priority: Int = Priority.PRIORITY_HIGH_ACCURACY

    companion object {
        private const val TAG = "LocationService"
        private const val CHANNEL_ID = "ridable_location_tracking"
        private const val NOTIFICATION_ID = 9999
        const val ACTION_START = "com.rnridablegpstracker.ACTION_START"
        const val ACTION_STOP = "com.rnridablegpstracker.ACTION_STOP"
    }

    inner class LocalBinder : Binder() {
        fun getService(): LocationService = this@LocationService
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service onCreate")
        createNotificationChannel()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
    }

    override fun onBind(intent: Intent?): IBinder {
        Log.d(TAG, "Service onBind")
        return binder
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand with action: ${intent?.action}")
        
        when (intent?.action) {
            ACTION_START -> {
                Log.d(TAG, "Starting foreground tracking")
                startForegroundTracking()
            }
            ACTION_STOP -> {
                Log.d(TAG, "Stopping foreground tracking")
                stopForegroundTracking()
                stopSelf()
            }
        }
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "GPS Location Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Tracking your ride location with GPS"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "Notification channel created")
        }
    }

    private fun createNotification(): Notification {
        val locationText = if (lastLocation != null) {
            val provider = if (lastLocation!!.provider != null) lastLocation!!.provider else "unknown"
            "Provider: $provider\n" +
            "Lat: ${String.format("%.6f", lastLocation!!.latitude)}\n" +
            "Lng: ${String.format("%.6f", lastLocation!!.longitude)}\n" +
            "Speed: ${String.format("%.1f", if (lastLocation!!.hasSpeed()) lastLocation!!.speed * 3.6 else 0f)} km/h\n" +
            "Accuracy: ${String.format("%.1f", lastLocation!!.accuracy)}m"
        } else {
            "Waiting for GPS signal..."
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🚴 GPS Tracking Active")
            .setContentText(locationText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(locationText))
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    fun configure(
        distanceFilter: Float,
        updateInterval: Long,
        fastestInterval: Long,
        desiredAccuracy: String
    ) {
        this.distanceFilter = distanceFilter
        this.updateInterval = updateInterval
        this.fastestInterval = fastestInterval
        this.priority = when (desiredAccuracy) {
            "high" -> Priority.PRIORITY_HIGH_ACCURACY
            "medium" -> Priority.PRIORITY_BALANCED_POWER_ACCURACY
            "low" -> Priority.PRIORITY_LOW_POWER
            else -> Priority.PRIORITY_HIGH_ACCURACY
        }
        Log.d(TAG, "Configured: distance=$distanceFilter, interval=$updateInterval, priority=$priority")
    }

    fun startForegroundTracking() {
        if (isForegroundStarted) {
            Log.d(TAG, "Foreground tracking already started")
            return
        }
        
        try {
            Log.d(TAG, "Creating GPS-only location request for exercise tracking")
            
            // GPS 전용 설정 (운동 앱용)
            val locationRequest = LocationRequest.Builder(
                Priority.PRIORITY_HIGH_ACCURACY,  // GPS 우선
                updateInterval
            ).apply {
                setMaxUpdateDelayMillis(updateInterval * 2)
                setMinUpdateIntervalMillis(fastestInterval)
                setMinUpdateDistanceMeters(distanceFilter)
                
                // 운동 앱 최적화 설정
                setWaitForAccurateLocation(true)  // 정확한 위치 대기
                setGranularity(Granularity.GRANULARITY_FINE)  // 세밀한 위치 정보
            }.build()

            locationCallback = object : LocationCallback() {
                override fun onLocationResult(locationResult: LocationResult) {
                    locationResult.lastLocation?.let { location ->
                        // GPS Provider만 사용 (선택적 필터링)
                        if (location.provider == "gps" || location.provider == "fused") {
                            lastLocation = location
                            Log.d(TAG, "GPS Location received: provider=${location.provider}, lat=${location.latitude}, lng=${location.longitude}, speed=${location.speed}, accuracy=${location.accuracy}m")
                            sendLocationUpdate(location)
                        } else {
                            Log.d(TAG, "Ignoring non-GPS location from provider: ${location.provider}")
                        }
                    }
                }
            }

            Log.d(TAG, "Requesting GPS location updates")
            fusedLocationClient?.requestLocationUpdates(
                locationRequest,
                locationCallback!!,
                Looper.getMainLooper()
            )

            // 마지막 위치를 1초마다 반복 전송하는 Runnable 시작
            startRepeatLocationUpdates()

            // Start foreground service
            Log.d(TAG, "Starting foreground service with notification")
            startForeground(NOTIFICATION_ID, createNotification())
            isForegroundStarted = true
            Log.d(TAG, "GPS tracking started successfully")
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception while starting GPS tracking", e)
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Error starting GPS tracking", e)
            throw e
        }
    }

    private fun startRepeatLocationUpdates() {
        Log.d(TAG, "Starting repeat location updates (1 second interval)")
        
        repeatLocationRunnable = object : Runnable {
            override fun run() {
                // 마지막 GPS 위치가 있으면 1초마다 전송
                lastLocation?.let { location ->
                    Log.d(TAG, "Repeating last GPS location (for 1-second interval)")
                    sendLocationUpdate(location)
                }
                
                // 1초 후 다시 실행
                handler.postDelayed(this, 1000L)
            }
        }
        
        // 즉시 시작
        handler.post(repeatLocationRunnable!!)
    }

    private fun stopRepeatLocationUpdates() {
        repeatLocationRunnable?.let {
            handler.removeCallbacks(it)
            Log.d(TAG, "Stopped repeat location updates")
        }
        repeatLocationRunnable = null
    }

    private fun sendLocationUpdate(location: Location) {
        locationListener?.invoke(location)
        updateNotification()
    }

    fun stopForegroundTracking() {
        Log.d(TAG, "Stopping GPS tracking")
        
        // 반복 업데이트 중지
        stopRepeatLocationUpdates()
        
        locationCallback?.let {
            fusedLocationClient?.removeLocationUpdates(it)
            Log.d(TAG, "GPS location updates removed")
        }
        locationCallback = null
        
        if (isForegroundStarted) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            isForegroundStarted = false
            Log.d(TAG, "GPS tracking stopped and notification removed")
        }
    }

    fun setLocationListener(listener: (Location) -> Unit) {
        locationListener = listener
        Log.d(TAG, "Location listener set")
    }

    fun removeLocationListener() {
        locationListener = null
        Log.d(TAG, "Location listener removed")
    }

    fun getLastLocation(): Location? = lastLocation

    fun isTracking(): Boolean = isForegroundStarted

    private fun updateNotification() {
        if (isForegroundStarted) {
            val notification = createNotification()
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.notify(NOTIFICATION_ID, notification)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service onDestroy")
        stopForegroundTracking()
    }
}
