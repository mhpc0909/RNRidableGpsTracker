package com.rnridablegpstracker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
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
import kotlin.math.sqrt
import kotlin.math.abs

class LocationService : Service(), SensorEventListener {

    private val binder = LocalBinder()
    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var lastLocation: Location? = null
    private var locationListener: ((Location, SensorData?) -> Unit)? = null
    private var isForegroundStarted = false
    private var isNewLocationAvailable = false
    
    // 센서 관련
    private var sensorManager: SensorManager? = null
    private var pressureSensor: Sensor? = null
    private var accelerometerSensor: Sensor? = null
    private var gyroscopeSensor: Sensor? = null
    
    // 기압계 관련
    private var referencePressure: Float? = null
    private var currentPressure: Float? = null
    private var relativeAltitude: Float = 0f
    private var startGpsAltitude: Float? = null
    private var enhancedAltitude: Float = 0f
    
    // 🆕 가속계 관련
    private var lastAccelerometerData: FloatArray = FloatArray(3)
    private var accelerometerTimestamp: Long = 0
    private val accelerometerBuffer = mutableListOf<AccelerometerReading>()
    private val maxBufferSize = 10 // 최근 10개 데이터
    
    // 🆕 자이로스코프 관련
    private var lastGyroscopeData: FloatArray = FloatArray(3)
    private var gyroscopeTimestamp: Long = 0
    private val gyroscopeBuffer = mutableListOf<GyroscopeReading>()
    
    // Kalman 필터 상태 변수
    private var kalmanLat: Double = 0.0
    private var kalmanLng: Double = 0.0
    private var variance: Double = 0.0
    private var isKalmanInitialized = false
    
    // 운동 타입별 필터 파라미터
    private var processNoise: Double = 0.0
    private var useKalmanFilter: Boolean = false
    private var exerciseType: String = "bicycle"
    private var advancedTracking: Boolean = false
    
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
        
        private const val SEA_LEVEL_PRESSURE = 1013.25f
        private const val GRAVITY = 9.81f
    }
    
    // 🆕 센서 데이터 클래스들
    data class AccelerometerReading(
        val x: Float,
        val y: Float,
        val z: Float,
        val timestamp: Long
    )
    
    data class GyroscopeReading(
        val x: Float,
        val y: Float,
        val z: Float,
        val timestamp: Long
    )
    
    data class BarometerData(
        val pressure: Float,
        val relativeAltitude: Float,
        val enhancedAltitude: Float
    )
    
    // 🆕 운동 분석 데이터
    data class MotionAnalysis(
        val roadSurfaceQuality: String,      // "smooth", "rough", "very_rough"
        val vibrationIntensity: Float,       // 0.0 ~ 1.0
        val corneringIntensity: Float,       // 0.0 ~ 1.0
        val inclineAngle: Float,             // -90 ~ 90 (도)
        val isClimbing: Boolean,
        val isDescending: Boolean,
        val verticalAcceleration: Float
    )
    
    // 🆕 통합 센서 데이터
    data class SensorData(
        val barometer: BarometerData?,
        val accelerometer: AccelerometerData?,
        val gyroscope: GyroscopeData?,
        val motionAnalysis: MotionAnalysis?
    )
    
    data class AccelerometerData(
        val x: Float,
        val y: Float,
        val z: Float,
        val magnitude: Float
    )
    
    data class GyroscopeData(
        val x: Float,
        val y: Float,
        val z: Float,
        val rotationRate: Float
    )

    inner class LocalBinder : Binder() {
        fun getService(): LocationService = this@LocationService
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service onCreate")
        createNotificationChannel()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        setupSensors()
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
            }
        }
        return START_STICKY
    }

    private fun setupSensors() {
        sensorManager = getSystemService(Context.SENSOR_SERVICE) as SensorManager
        
        // 기압계
        pressureSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_PRESSURE)
        if (pressureSensor != null) {
            Log.d(TAG, "✅ Barometer available: ${pressureSensor!!.name}")
        }
        
        // 🆕 가속계
        accelerometerSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (accelerometerSensor != null) {
            Log.d(TAG, "✅ Accelerometer available: ${accelerometerSensor!!.name}")
        }
        
        // 🆕 자이로스코프
        gyroscopeSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        if (gyroscopeSensor != null) {
            Log.d(TAG, "✅ Gyroscope available: ${gyroscopeSensor!!.name}")
        }
    }

    private fun startSensors() {
        // 기압계 시작
        pressureSensor?.let { sensor ->
            sensorManager?.registerListener(
                this,
                sensor,
                SensorManager.SENSOR_DELAY_NORMAL
            )
            Log.d(TAG, "📊 Barometer started")
        }
        
        // 🆕 가속계 시작 (advancedTracking일 때만)
        if (advancedTracking) {
            accelerometerSensor?.let { sensor ->
                sensorManager?.registerListener(
                    this,
                    sensor,
                    SensorManager.SENSOR_DELAY_GAME // 50Hz 정도
                )
                Log.d(TAG, "📊 Accelerometer started (advanced tracking)")
            }
            
            // 🆕 자이로스코프 시작
            gyroscopeSensor?.let { sensor ->
                sensorManager?.registerListener(
                    this,
                    sensor,
                    SensorManager.SENSOR_DELAY_GAME
                )
                Log.d(TAG, "📊 Gyroscope started (advanced tracking)")
            }
        }
    }

    private fun stopSensors() {
        sensorManager?.unregisterListener(this)
        
        // 상태 초기화
        referencePressure = null
        currentPressure = null
        relativeAltitude = 0f
        startGpsAltitude = null
        enhancedAltitude = 0f
        
        accelerometerBuffer.clear()
        gyroscopeBuffer.clear()
        lastAccelerometerData = FloatArray(3)
        lastGyroscopeData = FloatArray(3)
        
        Log.d(TAG, "📊 All sensors stopped")
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return
        
        when (event.sensor.type) {
            Sensor.TYPE_PRESSURE -> handlePressureData(event)
            Sensor.TYPE_ACCELEROMETER -> handleAccelerometerData(event)
            Sensor.TYPE_GYROSCOPE -> handleGyroscopeData(event)
        }
    }
    
    // 기압계 데이터 처리
    private fun handlePressureData(event: SensorEvent) {
        val pressure = event.values[0]
        currentPressure = pressure
        
        if (referencePressure == null) {
            referencePressure = pressure
            Log.d(TAG, "Reference pressure set: $pressure hPa")
        }
        
        referencePressure?.let { refPressure ->
            relativeAltitude = 44330f * (1f - (pressure / refPressure).pow(0.1903f))
            
            lastLocation?.let { location ->
                if (location.hasAltitude() && startGpsAltitude != null) {
                    val gpsAlt = location.altitude.toFloat()
                    val baroAltitude = startGpsAltitude!! + relativeAltitude
                    enhancedAltitude = (gpsAlt * 0.3f) + (baroAltitude * 0.7f)
                }
            }
        }
    }
    
    // 🆕 가속계 데이터 처리
    private fun handleAccelerometerData(event: SensorEvent) {
        if (!advancedTracking) return
        
        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        val timestamp = System.currentTimeMillis()
        
        lastAccelerometerData[0] = x
        lastAccelerometerData[1] = y
        lastAccelerometerData[2] = z
        accelerometerTimestamp = timestamp
        
        // 버퍼에 추가
        val reading = AccelerometerReading(x, y, z, timestamp)
        accelerometerBuffer.add(reading)
        
        // 버퍼 크기 제한
        if (accelerometerBuffer.size > maxBufferSize) {
            accelerometerBuffer.removeAt(0)
        }
    }
    
    // 🆕 자이로스코프 데이터 처리
    private fun handleGyroscopeData(event: SensorEvent) {
        if (!advancedTracking) return
        
        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        val timestamp = System.currentTimeMillis()
        
        lastGyroscopeData[0] = x
        lastGyroscopeData[1] = y
        lastGyroscopeData[2] = z
        gyroscopeTimestamp = timestamp
        
        // 버퍼에 추가
        val reading = GyroscopeReading(x, y, z, timestamp)
        gyroscopeBuffer.add(reading)
        
        if (gyroscopeBuffer.size > maxBufferSize) {
            gyroscopeBuffer.removeAt(0)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    // 🆕 운동 분석 생성
    private fun generateMotionAnalysis(): MotionAnalysis? {
        if (!advancedTracking || accelerometerBuffer.isEmpty()) {
            return null
        }
        
        // 1. 노면 상태 분석 (가속도 변화율)
        val vibrationIntensity = calculateVibrationIntensity()
        val roadSurfaceQuality = when {
            vibrationIntensity < 0.2f -> "smooth"
            vibrationIntensity < 0.5f -> "rough"
            else -> "very_rough"
        }
        
        // 2. 코너링 강도 (자이로스코프 Z축)
        val corneringIntensity = if (gyroscopeBuffer.isNotEmpty()) {
            val avgRotationZ = gyroscopeBuffer.map { abs(it.z) }.average().toFloat()
            (avgRotationZ / 3.0f).coerceIn(0f, 1f) // 정규화
        } else {
            0f
        }
        
        // 3. 경사도 분석 (가속도계 기반)
        val (inclineAngle, isClimbing, isDescending) = calculateIncline()
        
        // 4. 수직 가속도 (오르막/내리막 강도)
        val verticalAcceleration = lastAccelerometerData[2] - GRAVITY
        
        return MotionAnalysis(
            roadSurfaceQuality = roadSurfaceQuality,
            vibrationIntensity = vibrationIntensity,
            corneringIntensity = corneringIntensity,
            inclineAngle = inclineAngle,
            isClimbing = isClimbing,
            isDescending = isDescending,
            verticalAcceleration = verticalAcceleration
        )
    }
    
    // 🆕 진동 강도 계산 (노면 품질)
    private fun calculateVibrationIntensity(): Float {
        if (accelerometerBuffer.size < 2) return 0f
        
        var totalVariation = 0f
        for (i in 1 until accelerometerBuffer.size) {
            val prev = accelerometerBuffer[i - 1]
            val curr = accelerometerBuffer[i]
            
            val dx = curr.x - prev.x
            val dy = curr.y - prev.y
            val dz = curr.z - prev.z
            
            totalVariation += sqrt(dx * dx + dy * dy + dz * dz)
        }
        
        val avgVariation = totalVariation / (accelerometerBuffer.size - 1)
        
        // 정규화 (경험적 값: 0.5 ~ 3.0 범위를 0 ~ 1로)
        return ((avgVariation - 0.5f) / 2.5f).coerceIn(0f, 1f)
    }
    
    // 🆕 경사도 계산
    private fun calculateIncline(): Triple<Float, Boolean, Boolean> {
        if (accelerometerBuffer.isEmpty()) {
            return Triple(0f, false, false)
        }
        
        // 최근 데이터의 평균
        val avgX = accelerometerBuffer.map { it.x }.average().toFloat()
        val avgY = accelerometerBuffer.map { it.y }.average().toFloat()
        val avgZ = accelerometerBuffer.map { it.z }.average().toFloat()
        
        // 중력 방향을 기준으로 경사도 계산
        // 기기가 수평일 때 Z ≈ 9.81, X ≈ 0, Y ≈ 0
        // 앞으로 기울면 Y가 증가, 뒤로 기울면 Y가 감소
        
        val totalAccel = sqrt(avgX * avgX + avgY * avgY + avgZ * avgZ)
        val pitchAngle = Math.toDegrees(
            kotlin.math.atan2(avgY.toDouble(), avgZ.toDouble())
        ).toFloat()
        
        val isClimbing = pitchAngle > 5f  // 5도 이상 오르막
        val isDescending = pitchAngle < -5f  // 5도 이상 내리막
        
        return Triple(pitchAngle, isClimbing, isDescending)
    }

    private fun initKalmanFilter(location: Location) {
        kalmanLat = location.latitude
        kalmanLng = location.longitude
        variance = (location.accuracy * location.accuracy).toDouble()
        isKalmanInitialized = true
        
        Log.d(TAG, "[KalmanFilter] Initialized: lat=$kalmanLat, lng=$kalmanLng, variance=$variance")
    }

    private fun resetKalmanFilter() {
        isKalmanInitialized = false
        variance = 0.0
        Log.d(TAG, "[KalmanFilter] Reset")
    }

    private fun applyKalmanFilter(newLocation: Location): Location {
        if (!isKalmanInitialized) {
            initKalmanFilter(newLocation)
            return newLocation
        }
        
        val measurementNoise = (newLocation.accuracy * newLocation.accuracy).toDouble()
        val predictedVariance = variance + processNoise
        val kalmanGain = predictedVariance / (predictedVariance + measurementNoise)
        
        kalmanLat = kalmanLat + kalmanGain * (newLocation.latitude - kalmanLat)
        kalmanLng = kalmanLng + kalmanGain * (newLocation.longitude - kalmanLng)
        variance = (1.0 - kalmanGain) * predictedVariance
        
        return Location(newLocation).apply {
            latitude = kalmanLat
            longitude = kalmanLng
            accuracy = sqrt(variance).toFloat()
        }
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
        }
    }

    private fun createNotification(): Notification {
        val kalmanStatus = if (useKalmanFilter) "ON" else "OFF"
        val advancedStatus = if (advancedTracking) "ON" else "OFF"
        
        val locationText = if (lastLocation != null) {
            val baseInfo = "Exercise: $exerciseType (K:$kalmanStatus, ADV:$advancedStatus)\n" +
                    "Lat: ${String.format("%.6f", lastLocation!!.latitude)}\n" +
                    "Lng: ${String.format("%.6f", lastLocation!!.longitude)}\n" +
                    "Speed: ${String.format("%.1f", if (lastLocation!!.hasSpeed()) lastLocation!!.speed * 3.6 else 0f)} km/h"
            
            val motionInfo = if (advancedTracking && accelerometerBuffer.isNotEmpty()) {
                val analysis = generateMotionAnalysis()
                analysis?.let {
                    "\nSurface: ${it.roadSurfaceQuality}\n" +
                    "Vibration: ${String.format("%.2f", it.vibrationIntensity)}\n" +
                    "Incline: ${String.format("%.1f", it.inclineAngle)}°"
                } ?: ""
            } else ""
            
            baseInfo + motionInfo
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
        exerciseType: String = "bicycle",
        advancedTracking: Boolean = false
    ) {
        this.distanceFilter = distanceFilter
        this.updateInterval = interval
        this.fastestInterval = fastestInterval
        this.exerciseType = exerciseType
        this.advancedTracking = advancedTracking
        
        when (exerciseType) {
            "bicycle" -> {
                this.priority = Priority.PRIORITY_HIGH_ACCURACY
                this.useKalmanFilter = false
                this.processNoise = 0.0
                Log.d(TAG, "🚴 Bicycle mode: Kalman=$useKalmanFilter, Advanced=$advancedTracking")
            }
            "running" -> {
                this.priority = Priority.PRIORITY_HIGH_ACCURACY
                this.useKalmanFilter = true
                this.processNoise = 0.5
                Log.d(TAG, "🏃 Running mode: Kalman=$useKalmanFilter, Advanced=$advancedTracking")
            }
            "hiking" -> {
                this.priority = Priority.PRIORITY_HIGH_ACCURACY
                this.useKalmanFilter = true
                this.processNoise = 1.0
                Log.d(TAG, "🥾 Hiking mode: Kalman=$useKalmanFilter, Advanced=$advancedTracking")
            }
            "walking" -> {
                this.priority = Priority.PRIORITY_HIGH_ACCURACY
                this.useKalmanFilter = true
                this.processNoise = 2.0
                Log.d(TAG, "🚶 Walking mode: Kalman=$useKalmanFilter, Advanced=$advancedTracking")
            }
        }
    }

    fun startForegroundTracking() {
        if (isForegroundStarted) {
            Log.d(TAG, "⚠️ Already started, stopping first...")
            stopForegroundTracking()
            handler.postDelayed({
                startForegroundTrackingInternal()
            }, 100)
        } else {
            startForegroundTrackingInternal()
        }
    }

    private fun startForegroundTrackingInternal() {
        try {
            Log.d(TAG, "🚀 Starting GPS tracking: $exerciseType (Advanced: $advancedTracking)")
            
            locationCallback?.let { callback ->
                fusedLocationClient?.removeLocationUpdates(callback)
            }
            
            resetKalmanFilter()
            lastLocation = null
            isNewLocationAvailable = false
            lastSendTime = 0
            
            val locationRequest = LocationRequest.Builder(
                Priority.PRIORITY_HIGH_ACCURACY,
                updateInterval
            ).apply {
                setMaxUpdateDelayMillis(updateInterval * 2)
                setMinUpdateIntervalMillis(fastestInterval)
                setMinUpdateDistanceMeters(distanceFilter)
                setWaitForAccurateLocation(true)
                setGranularity(Granularity.GRANULARITY_FINE)
            }.build()

            locationCallback = object : LocationCallback() {
                override fun onLocationResult(locationResult: LocationResult) {
                    locationResult.lastLocation?.let { location ->
                        if (location.provider == "gps" || location.provider == "fused") {
                            val processedLocation = if (useKalmanFilter) {
                                applyKalmanFilter(location)
                            } else {
                                location
                            }
                            
                            if (startGpsAltitude == null && processedLocation.hasAltitude()) {
                                startGpsAltitude = processedLocation.altitude.toFloat()
                                enhancedAltitude = startGpsAltitude!!
                            }
                            
                            lastLocation = processedLocation
                            isNewLocationAvailable = true
                        }
                    }
                }
            }

            fusedLocationClient?.requestLocationUpdates(
                locationRequest,
                locationCallback!!,
                Looper.getMainLooper()
            )

            startSensors()
            startRepeatLocationUpdates()

            startForeground(NOTIFICATION_ID, createNotification())
            isForegroundStarted = true
            Log.d(TAG, "✅ GPS tracking started successfully")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting GPS tracking", e)
            throw e
        }
    }

    private fun startRepeatLocationUpdates() {
        repeatLocationRunnable?.let {
            handler.removeCallbacks(it)
        }
        
        lastSendTime = System.currentTimeMillis()
        
        repeatLocationRunnable = object : Runnable {
            override fun run() {
                if (!isForegroundStarted) return
                
                val now = System.currentTimeMillis()
                if (now - lastSendTime >= 1000) {
                    lastLocation?.let { location ->
                        sendLocationUpdate(location, isNewLocationAvailable)
                        if (isNewLocationAvailable) {
                            isNewLocationAvailable = false
                        }
                        lastSendTime = now
                    }
                }
                
                if (isForegroundStarted) {
                    handler.postDelayed(this, 1000L)
                }
            }
        }
        
        handler.postDelayed(repeatLocationRunnable!!, 1000L)
    }

    private fun stopRepeatLocationUpdates() {
        repeatLocationRunnable?.let {
            handler.removeCallbacks(it)
        }
        repeatLocationRunnable = null
    }

    private fun sendLocationUpdate(location: Location, isNew: Boolean) {
        if (!isForegroundStarted) return
        
        // 기압계 데이터
        val barometerData = currentPressure?.let { pressure ->
            BarometerData(
                pressure = pressure,
                relativeAltitude = relativeAltitude,
                enhancedAltitude = enhancedAltitude
            )
        }
        
        // 🆕 가속계 데이터
        val accelerometerData = if (advancedTracking && accelerometerTimestamp > 0) {
            val magnitude = sqrt(
                lastAccelerometerData[0] * lastAccelerometerData[0] +
                lastAccelerometerData[1] * lastAccelerometerData[1] +
                lastAccelerometerData[2] * lastAccelerometerData[2]
            )
            AccelerometerData(
                x = lastAccelerometerData[0],
                y = lastAccelerometerData[1],
                z = lastAccelerometerData[2],
                magnitude = magnitude
            )
        } else null
        
        // 🆕 자이로스코프 데이터
        val gyroscopeData = if (advancedTracking && gyroscopeTimestamp > 0) {
            val rotationRate = sqrt(
                lastGyroscopeData[0] * lastGyroscopeData[0] +
                lastGyroscopeData[1] * lastGyroscopeData[1] +
                lastGyroscopeData[2] * lastGyroscopeData[2]
            )
            GyroscopeData(
                x = lastGyroscopeData[0],
                y = lastGyroscopeData[1],
                z = lastGyroscopeData[2],
                rotationRate = rotationRate
            )
        } else null
        
        // 🆕 운동 분석 데이터
        val motionAnalysis = if (advancedTracking) {
            generateMotionAnalysis()
        } else null
        
        val sensorData = SensorData(
            barometer = barometerData,
            accelerometer = accelerometerData,
            gyroscope = gyroscopeData,
            motionAnalysis = motionAnalysis
        )
        
        locationListener?.invoke(location, sensorData)
        updateNotification()
    }

    fun stopForegroundTracking() {
        Log.d(TAG, "🛑 Stopping GPS tracking")
        
        stopRepeatLocationUpdates()
        
        locationCallback?.let { callback ->
            fusedLocationClient?.removeLocationUpdates(callback)
        }
        locationCallback = null
        
        stopSensors()
        resetKalmanFilter()
        
        lastLocation = null
        isNewLocationAvailable = false
        lastSendTime = 0
        
        if (isForegroundStarted) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
            isForegroundStarted = false
            Log.d(TAG, "✅ GPS tracking stopped")
        }
    }

    fun setLocationListener(listener: (Location, SensorData?) -> Unit) {
        locationListener = listener
    }

    fun removeLocationListener() {
        locationListener = null
    }

    fun getLastLocation(): Location? = lastLocation
    
    fun getLastSensorData(): SensorData? {
        val barometerData = currentPressure?.let {
            BarometerData(currentPressure!!, relativeAltitude, enhancedAltitude)
        }
        
        val accelerometerData = if (advancedTracking && accelerometerTimestamp > 0) {
            val magnitude = sqrt(
                lastAccelerometerData[0] * lastAccelerometerData[0] +
                lastAccelerometerData[1] * lastAccelerometerData[1] +
                lastAccelerometerData[2] * lastAccelerometerData[2]
            )
            AccelerometerData(
                lastAccelerometerData[0],
                lastAccelerometerData[1],
                lastAccelerometerData[2],
                magnitude
            )
        } else null
        
        val gyroscopeData = if (advancedTracking && gyroscopeTimestamp > 0) {
            val rotationRate = sqrt(
                lastGyroscopeData[0] * lastGyroscopeData[0] +
                lastGyroscopeData[1] * lastGyroscopeData[1] +
                lastGyroscopeData[2] * lastGyroscopeData[2]
            )
            GyroscopeData(
                lastGyroscopeData[0],
                lastGyroscopeData[1],
                lastGyroscopeData[2],
                rotationRate
            )
        } else null
        
        val motionAnalysis = if (advancedTracking) generateMotionAnalysis() else null
        
        return SensorData(barometerData, accelerometerData, gyroscopeData, motionAnalysis)
    }
    
    fun isBarometerAvailable(): Boolean = pressureSensor != null
    fun isAccelerometerAvailable(): Boolean = accelerometerSensor != null
    fun isGyroscopeAvailable(): Boolean = gyroscopeSensor != null
    fun isTracking(): Boolean = isForegroundStarted
    fun getExerciseType(): String = exerciseType
    fun getAdvancedTracking(): Boolean = advancedTracking
    fun isUsingKalmanFilter(): Boolean = useKalmanFilter
    fun isKalmanFiltered(): Boolean = useKalmanFilter && isKalmanInitialized

    private fun updateNotification() {
        if (isForegroundStarted) {
            val notification = createNotification()
            val notificationManager = getSystemService(NotificationManager::class.java)
            notificationManager.notify(NOTIFICATION_ID, notification)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "💀 Service onDestroy")
        stopForegroundTracking()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "⚠️ App task removed")
        stopForegroundTracking()
        stopSelf()
    }
}