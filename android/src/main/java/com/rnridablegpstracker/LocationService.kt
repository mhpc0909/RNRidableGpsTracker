package com.rnridablegpstracker

import android.annotation.SuppressLint
import android.app.*
import android.content.Context
import android.content.Intent
import android.location.Location
import android.os.Build
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*

class LocationService : Service() {

    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    
    companion object {
        const val CHANNEL_ID = "location_service_channel"
        const val NOTIFICATION_ID = 1001
        const val ACTION_START = "ACTION_START_LOCATION_SERVICE"
        const val ACTION_STOP = "ACTION_STOP_LOCATION_SERVICE"
        private const val TAG = "LocationService"
        
        // Configuration keys
        const val EXTRA_INTERVAL = "interval"
        const val EXTRA_FASTEST_INTERVAL = "fastestInterval"
        const val EXTRA_DISTANCE_FILTER = "distanceFilter"
        const val EXTRA_PRIORITY = "priority"
        
        var isServiceRunning = false
            private set
        
        var locationListener: ((Location) -> Unit)? = null
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service onCreate")
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand called with action: ${intent?.action}")
        
        when (intent?.action) {
            ACTION_START -> {
                val interval = intent.getLongExtra(EXTRA_INTERVAL, 1000L)
                val fastestInterval = intent.getLongExtra(EXTRA_FASTEST_INTERVAL, 1000L)
                val distanceFilter = intent.getFloatExtra(EXTRA_DISTANCE_FILTER, 0f)
                val priority = intent.getIntExtra(EXTRA_PRIORITY, LocationRequest.PRIORITY_HIGH_ACCURACY)
                
                Log.d(TAG, "Starting foreground service with interval=$interval, fastestInterval=$fastestInterval")
                
                try {
                    val notification = createNotification()
                    startForeground(NOTIFICATION_ID, notification)
                    Log.d(TAG, "startForeground completed, notification displayed")
                    
                    startLocationUpdates(interval, fastestInterval, distanceFilter, priority)
                    isServiceRunning = true
                    Log.d(TAG, "Location updates started, isServiceRunning=true")
                } catch (e: Exception) {
                    Log.e(TAG, "Error starting foreground service", e)
                }
            }
            ACTION_STOP -> {
                Log.d(TAG, "Stopping service")
                stopLocationUpdates()
                stopForeground(true)
                stopSelf()
                isServiceRunning = false
                Log.d(TAG, "Service stopped")
            }
        }
        
        return START_STICKY
    }

    @SuppressLint("MissingPermission")
    private fun startLocationUpdates(
        interval: Long,
        fastestInterval: Long,
        distanceFilter: Float,
        priority: Int
    ) {
        Log.d(TAG, "startLocationUpdates called")
        
        val locationRequest = LocationRequest.create().apply {
            // Set both to 1 second to ensure consistent updates every 1 second
            this.interval = interval
            this.fastestInterval = fastestInterval
            this.priority = priority
            // Set distance filter to 0 to rely on time-based updates only
            this.smallestDisplacement = distanceFilter
        }

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                locationResult.lastLocation?.let { location ->
                    Log.d(TAG, "Location update: lat=${location.latitude}, lng=${location.longitude}, speed=${location.speed}")
                    locationListener?.invoke(location)
                    updateNotification(location)
                }
            }
        }

        try {
            fusedLocationClient?.requestLocationUpdates(
                locationRequest,
                locationCallback!!,
                Looper.getMainLooper()
            )
            Log.d(TAG, "Location updates requested successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Error requesting location updates", e)
        }
    }

    private fun stopLocationUpdates() {
        locationCallback?.let {
            fusedLocationClient?.removeLocationUpdates(it)
            Log.d(TAG, "Location updates removed")
        }
        locationCallback = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "GPS Tracking",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "GPS tracking service for cycling (1-second updates)"
                setShowBadge(false)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "Notification channel created")
        }
    }

    private fun createNotification(): Notification {
        Log.d(TAG, "Creating notification")
        
        val notificationIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            notificationIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )

        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("GPS Tracking Active")
            .setContentText("Recording your ride (1-second updates)...")
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()
        
        Log.d(TAG, "Notification created")
        return notification
    }

    private fun updateNotification(location: Location) {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("GPS Tracking Active")
            .setContentText("Speed: %.1f km/h | Acc: %.1fm".format(location.speed * 3.6, location.accuracy))
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service onDestroy")
        stopLocationUpdates()
        isServiceRunning = false
    }
}
