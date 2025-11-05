package com.gpstrackerexample

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.location.Location
import android.os.Binder
import android.os.Build
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

    companion object {
        private const val TAG = "LocationService"
        private const val CHANNEL_ID = "location_tracking_channel"
        private const val NOTIFICATION_ID = 1
        const val ACTION_START = "com.gpstrackerexample.ACTION_START"
        const val ACTION_STOP = "com.gpstrackerexample.ACTION_STOP"
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
            else -> {
                // 서비스가 시작되면 자동으로 포그라운드 서비스로 시작
                Log.d(TAG, "Starting foreground tracking (default)")
                startForegroundTracking()
            }
        }
        return START_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "GPS 위치 추적",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "GPS 위치 추적이 진행 중입니다"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "Notification channel created")
        }
    }

    private fun createNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val stopIntent = Intent(this, LocationService::class.java).apply {
            action = ACTION_STOP
        }
        val stopPendingIntent = PendingIntent.getService(
            this,
            0,
            stopIntent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        val locationText = if (lastLocation != null) {
            "위도: ${String.format("%.6f", lastLocation!!.latitude)}\n" +
            "경도: ${String.format("%.6f", lastLocation!!.longitude)}\n" +
            "속도: ${String.format("%.1f", if (lastLocation!!.hasSpeed()) lastLocation!!.speed * 3.6 else 0f)} km/h"
        } else {
            "위치를 가져오는 중..."
        }

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🚴 GPS 위치 추적 중 (1초 간격)")
            .setContentText(locationText)
            .setStyle(NotificationCompat.BigTextStyle().bigText(locationText))
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .addAction(
                android.R.drawable.ic_menu_close_clear_cancel,
                "중지",
                stopPendingIntent
            )
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
    }

    fun startForegroundTracking() {
        if (isForegroundStarted) {
            Log.d(TAG, "Foreground tracking already started")
            return
        }
        
        try {
            Log.d(TAG, "Creating location request")
            
            val locationRequest = LocationRequest.Builder(
                Priority.PRIORITY_HIGH_ACCURACY,
                1000  // 1초 간격
            ).apply {
                setMaxUpdateDelayMillis(2000)
                setMinUpdateIntervalMillis(1000)  // 최소 1초 간격
                setMinUpdateDistanceMeters(0f)  // 거리 필터 없음
            }.build()

            locationCallback = object : LocationCallback() {
                override fun onLocationResult(locationResult: LocationResult) {
                    locationResult.lastLocation?.let { location ->
                        lastLocation = location
                        Log.d(TAG, "Location update: lat=${location.latitude}, lng=${location.longitude}, speed=${location.speed}")
                        locationListener?.invoke(location)
                        // 알림 업데이트
                        updateNotification()
                    }
                }
            }

            Log.d(TAG, "Requesting location updates")
            fusedLocationClient?.requestLocationUpdates(
                locationRequest,
                locationCallback!!,
                Looper.getMainLooper()
            )

            // 포그라운드 서비스로 시작
            Log.d(TAG, "Starting foreground service with notification")
            startForeground(NOTIFICATION_ID, createNotification())
            isForegroundStarted = true
            Log.d(TAG, "Foreground service started successfully")
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception while starting foreground tracking", e)
            e.printStackTrace()
        } catch (e: Exception) {
            Log.e(TAG, "Error starting foreground tracking", e)
            e.printStackTrace()
        }
    }

    fun stopForegroundTracking() {
        Log.d(TAG, "Stopping foreground tracking")
        
        // 위치 업데이트 중지
        locationCallback?.let {
            fusedLocationClient?.removeLocationUpdates(it)
            Log.d(TAG, "Location updates removed")
        }
        locationCallback = null
        
        // 포그라운드 서비스 중지 및 알림 제거
        if (isForegroundStarted) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            isForegroundStarted = false
            Log.d(TAG, "Foreground service stopped and notification removed")
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
