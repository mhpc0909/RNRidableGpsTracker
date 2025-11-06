package com.rnridablegpstracker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import kotlin.math.pow

class LocationService : Service(), SensorEventListener {

    private val binder = LocalBinder()
    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var lastLocation: Location? = null
    private var locationListener: ((Location, BarometerData?) -> Unit)? = null
    private var isForegroundStarted = false
    private var isNewLocationAvailable = false
    
    // 기압계 관련
    private var sensorManager: SensorManager? = null
    private var pressureSensor: Sensor? = null
    private var referencePressure: Float? = null  // 시작점 기압
    private var currentPressure: Float? = null
    private var relativeAltitude: Float = 0f
    
    // 🆕 칼만 필터 관련
    private var startGpsAltitude: Float? = null
    private var enhancedAltitude: Float = 0f
    
    // 🆕 가중치 (조정 가능)
    private val GPS_WEIGHT = 0.3f  // GPS 신뢰도
    private val BARO_WEIGHT = 0.7f  // 기압계 신뢰도 (단기 변화에 민감)
    
    // 1초마다 마지막 위치 전송용
    private val handler = Handler(Looper.getMainLooper())
    private var repeatLocationRunnable: Runnable? = null
    private var lastSendTime: Long = 0
    
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
        
        // 기압-고도 변환 상수 (해수면 기압 기준)
        private const val SEA_LEVEL_PRESSURE = 1013.25f  // hPa
    }
    
    data class BarometerData(
        val pressure: Float,              // 현재 기압 (hPa)
        val relativeAltitude: Float,      // 상대 고도 (m)
        val enhancedAltitude: Float       // 보정된 고도 (m) - 칼만 필터 적용
    )

    inner class LocalBinder : Binder() {
        fun getService(): LocationService = this@LocationService
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service onCreate")
        createNotificationChannel()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        setupBarometer()
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

    private fun setupBarometer() {
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        pressureSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_PRESSURE)
        
        if (pressureSensor != null) {
            Log.d(TAG, "✅ Barometer sensor available: ${pressureSensor!!.name}")
        } else {
            Log.w(TAG, "⚠️ Barometer sensor not available on this device")
        }
    }

    private fun startBarometer() {
        pressureSensor?.let { sensor ->
            // 기압 센서 리스너 등록 (SENSOR_DELAY_NORMAL = ~200ms)
            sensorManager?.registerListener(
                this,
                sensor,
                SensorManager.SENSOR_DELAY_NORMAL
            )
            Log.d(TAG, "Barometer started")
        }
    }

    private fun stopBarometer() {
        pressureSensor?.let {
            sensorManager?.unregisterListener(this)
            referencePressure = null
            currentPressure = null
            relativeAltitude = 0f
            // 🆕 칼만 필터 변수 초기화
            startGpsAltitude = null
            enhancedAltitude = 0f
            Log.d(TAG, "Barometer stopped")
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event?.sensor?.type == Sensor.TYPE_PRESSURE) {
            val pressure = event.values[0]  // hPa (hectopascals)
            currentPressure = pressure
            
            // 첫 기압 측정 시 기준점으로 설정
            if (referencePressure == null) {
                referencePressure = pressure
                Log.d(TAG, "Reference pressure set: $pressure hPa")
            }
            
            // 기압 차이로 상대 고도 계산
            // 고도 = 44330 * (1 - (P/P0)^0.1903)
            referencePressure?.let { refPressure ->
                relativeAltitude = 44330f * (1f - (pressure / refPressure).pow(0.1903f))
                
                // 🆕 칼만 필터 융합 (GPS와 기압계 데이터 결합)
                lastLocation?.let { location ->
                    if (location.hasAltitude() && startGpsAltitude != null) {
                        val gpsAlt = location.altitude.toFloat()
                        
                        // 기압계 기반 절대 고도 = 시작 GPS 고도 + 상대 변화량
                        val baroAltitude = startGpsAltitude!! + relativeAltitude
                        
                        // 칼만 필터: GPS(30%) + 기압계(70%) 가중 평균
                        enhancedAltitude = (gpsAlt * GPS_WEIGHT) + (baroAltitude * BARO_WEIGHT)
                        
                        Log.d(TAG, "📊 Altitude fusion: GPS=${String.format("%.1f", gpsAlt)}m, " +
                                "Baro=${String.format("%.1f", baroAltitude)}m, " +
                                "Enhanced=${String.format("%.1f", enhancedAltitude)}m")
                    }
                }
                
                Log.d(TAG, "Barometer: pressure=$pressure hPa, relative altitude=$relativeAltitude m")
            }
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        // 정확도 변경 시 (필요시 처리)
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
            val barometerText = currentPressure?.let { 
                "\nPressure: ${String.format("%.1f", it)} hPa" +
                "\nGPS Alt: ${String.format("%.1f", lastLocation!!.altitude)}m" +
                "\nEnhanced Alt: ${String.format("%.1f", enhancedAltitude)}m" +  // 🆕
                "\nAlt Δ: ${String.format("%.1f", relativeAltitude)}m"
            } ?: ""
            
            "Provider: $provider\n" +
            "Lat: ${String.format("%.6f", lastLocation!!.latitude)}\n" +
            "Lng: ${String.format("%.6f", lastLocation!!.longitude)}\n" +
            "Speed: ${String.format("%.1f", if (lastLocation!!.hasSpeed()) lastLocation!!.speed * 3.6 else 0f)} km/h\n" +
            "Accuracy: ${String.format("%.1f", lastLocation!!.accuracy)}m" +
            barometerText
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
        interval: Long,
        fastestInterval: Long,
        desiredAccuracy: String,
        exerciseType: String = "bicycle"  // 🆕 기본값 bicycle
    ) {
        this.distanceFilter = distanceFilter
        this.updateInterval = interval
        this.fastestInterval = fastestInterval
        
        when (exerciseType) {
            "bicycle" -> {
                // 자전거 특화 설정
                this.priority = Priority.PRIORITY_HIGH_ACCURACY
            }
            "running" -> {
                // 러닝 특화 설정
                this.priority = Priority.PRIORITY_HIGH_ACCURACY
            }
            "hiking" -> {
                // 하이킹 특화 설정
                this.priority = Priority.PRIORITY_HIGH_ACCURACY
            }
            "walking" -> {
                // 걷기 특화 설정
                this.priority = Priority.PRIORITY_BALANCED_POWER_ACCURACY
            }
        }
        
        Log.d(TAG, "Configured: distance=$distanceFilter, interval=$interval, priority=$priority")
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
                            // 🆕 첫 GPS 고도를 기준점으로 설정
                            if (startGpsAltitude == null && location.hasAltitude()) {
                                startGpsAltitude = location.altitude.toFloat()
                                enhancedAltitude = startGpsAltitude!!
                                Log.d(TAG, "🎯 Start GPS altitude set: ${startGpsAltitude}m")
                            }
                            
                            lastLocation = location
                            isNewLocationAvailable = true
                            
                            Log.d(TAG, "🆕 NEW GPS Location received: provider=${location.provider}, lat=${location.latitude}, lng=${location.longitude}")
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

            // 기압계 시작
            startBarometer()

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
        
        lastSendTime = System.currentTimeMillis()
        
        repeatLocationRunnable = object : Runnable {
            override fun run() {
                // 추적 중이 아니면 중단
                if (!isForegroundStarted) {
                    Log.d(TAG, "⚠️ Tracking stopped - cancelling repeat updates")
                    return
                }
                
                val now = System.currentTimeMillis()
                val elapsed = now - lastSendTime
                
                // 1초 이상 경과했을 때만 전송
                if (elapsed >= 1000) {
                    lastLocation?.let { location ->
                        val isNew = isNewLocationAvailable
                        if (isNew) {
                            Log.d(TAG, "🆕 Sending NEW location data")
                        }
                        sendLocationUpdate(location, isNew = isNew)
                        if (isNew) {
                            isNewLocationAvailable = false
                        }
                        lastSendTime = now
                    }
                }
                
                // 다음 실행 예약 (추적 중일 때만)
                if (isForegroundStarted) {
                    handler.postDelayed(this, 1000L)
                }
            }
        }
        
        // 1초 후 시작
        handler.postDelayed(repeatLocationRunnable!!, 1000L)
    }

    private fun stopRepeatLocationUpdates() {
        repeatLocationRunnable?.let {
            handler.removeCallbacks(it)
            Log.d(TAG, "Stopped repeat location updates")
        }
        repeatLocationRunnable = null
    }

    private fun sendLocationUpdate(location: Location, isNew: Boolean) {
        // 추적 중이 아니면 전송하지 않음
        if (!isForegroundStarted) {
            Log.d(TAG, "⚠️ Not tracking - skipping location update")
            return
        }
        
        val barometerData = currentPressure?.let { pressure ->
            BarometerData(
                pressure = pressure,
                relativeAltitude = relativeAltitude,
                enhancedAltitude = enhancedAltitude  // 🆕 칼만 필터 융합 고도
            )
        }
        
        locationListener?.invoke(location, barometerData)
        updateNotification()
    }

    fun stopForegroundTracking() {
        Log.d(TAG, "Stopping GPS tracking")
        
        // 🔥 먼저 리스너 제거 (이벤트 전송 중지)
        removeLocationListener()
        
        // 반복 업데이트 중지
        stopRepeatLocationUpdates()
        
        // 기압계 중지
        stopBarometer()
        
        locationCallback?.let {
            fusedLocationClient?.removeLocationUpdates(it)
            Log.d(TAG, "GPS location updates removed")
        }
        locationCallback = null
        
        // 데이터 초기화
        lastLocation = null
        isNewLocationAvailable = false
        
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

    fun setLocationListener(listener: (Location, BarometerData?) -> Unit) {
        locationListener = listener
        Log.d(TAG, "Location listener set")
    }

    fun removeLocationListener() {
        locationListener = null
        Log.d(TAG, "Location listener removed")
    }

    fun getLastLocation(): Location? = lastLocation
    
    fun getLastBarometerData(): BarometerData? {
        return currentPressure?.let { pressure ->
            BarometerData(
                pressure = pressure,
                relativeAltitude = relativeAltitude,
                enhancedAltitude = enhancedAltitude  // 🆕
            )
        }
    }
    
    fun isBarometerAvailable(): Boolean = pressureSensor != null

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

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "⚠️ App task removed - stopping tracking service")
        
        // 앱이 종료되면 추적도 중지
        stopForegroundTracking()
        stopSelf()
    }
}