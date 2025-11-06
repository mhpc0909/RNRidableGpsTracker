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
import kotlin.math.min
import kotlin.math.max

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
    private val maxBufferSize = 10
    
    // 🆕 자이로스코프 관련
    private var lastGyroscopeData: FloatArray = FloatArray(3)
    private var gyroscopeTimestamp: Long = 0
    private val gyroscopeBuffer = mutableListOf<GyroscopeReading>()
    
    // Kalman 필터 (위치)
    private var kalmanLat: Double = 0.0
    private var kalmanLng: Double = 0.0
    private var variance: Double = 0.0
    private var isKalmanInitialized = false
    
    // 🆕 Kalman 필터 (고도)
    private var kalmanAltitude: Double = 0.0
    private var altitudeVariance: Double = 0.0
    private var isAltitudeKalmanInitialized = false
    private var altitudeProcessNoise: Double = 0.5
    
    // 운동 타입별 필터 파라미터
    private var processNoise: Double = 0.0
    private var useKalmanFilter: Boolean = false
    private var exerciseType: String = "bicycle"
    private var advancedTracking: Boolean = false
    
    // 🆕 통계 데이터
    private var sessionDistance: Double = 0.0          // 이동 거리 (m)
    private var sessionElevationGain: Double = 0.0     // 획득 고도 (m)
    private var sessionElevationLoss: Double = 0.0     // 상실 고도 (m)
    private var sessionMaxSpeed: Float = 0f            // 최고 속도 (m/s)
    private var sessionMovingTime: Double = 0.0        // 이동 시간 (초)
    private var sessionElapsedTime: Double = 0.0       // 총 경과 시간 (초)
    private var sessionStartTime: Long = 0             // 세션 시작 시간
    private var previousLocation: Location? = null     // 이전 위치
    private var previousAltitude: Double = 0.0         // 이전 고도
    private var lastUpdateTime: Long = 0               // 마지막 업데이트 시간
    
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
    
    // 센서 데이터 클래스들
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
    
    data class MotionAnalysis(
        val roadSurfaceQuality: String,
        val vibrationIntensity: Float,
        val corneringIntensity: Float,
        val inclineAngle: Float,
        val isClimbing: Boolean,
        val isDescending: Boolean,
        val verticalAcceleration: Float
    )
    
    // 🆕 Grade 데이터
    data class GradeData(
        val grade: Float,              // 경사도 (%)
        val gradeCategory: String      // flat, gentle, moderate, steep, very_steep
    )
    
    // 🆕 통계 데이터
    data class SessionStats(
        val distance: Double,           // 이동 거리 (m)
        val elevationGain: Double,      // 획득 고도 (m)
        val elevationLoss: Double,      // 상실 고도 (m)
        val movingTime: Double,         // 이동 시간 (초)
        val elapsedTime: Double,        // 총 경과 시간 (초)
        val maxSpeed: Float,            // 최고 속도 (m/s)
        val avgSpeed: Double,           // 평균 속도 (m/s) - elapsed 기준
        val movingAvgSpeed: Double      // 이동 평균 속도 (m/s) - moving 기준
    )
    
    data class SensorData(
        val barometer: BarometerData?,
        val accelerometer: AccelerometerData?,
        val gyroscope: GyroscopeData?,
        val motionAnalysis: MotionAnalysis?,
        val grade: GradeData?,           // 🆕 Grade 데이터
        val sessionStats: SessionStats?  // 🆕 세션 통계
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
        
        pressureSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_PRESSURE)
        if (pressureSensor != null) {
            Log.d(TAG, "✅ Barometer available: ${pressureSensor!!.name}")
        }
        
        accelerometerSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (accelerometerSensor != null) {
            Log.d(TAG, "✅ Accelerometer available: ${accelerometerSensor!!.name}")
        }
        
        gyroscopeSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        if (gyroscopeSensor != null) {
            Log.d(TAG, "✅ Gyroscope available: ${gyroscopeSensor!!.name}")
        }
    }

    private fun startSensors() {
        pressureSensor?.let { sensor ->
            sensorManager?.registerListener(
                this,
                sensor,
                SensorManager.SENSOR_DELAY_NORMAL
            )
            Log.d(TAG, "📊 Barometer started")
        }
        
        if (advancedTracking) {
            accelerometerSensor?.let { sensor ->
                sensorManager?.registerListener(
                    this,
                    sensor,
                    SensorManager.SENSOR_DELAY_GAME
                )
                Log.d(TAG, "📊 Accelerometer started (advanced tracking)")
            }
            
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
                    
                    // GPS 30% + 기압계 70%
                    val rawEnhancedAltitude = (gpsAlt * 0.3f) + (baroAltitude * 0.7f)
                    
                    // 🆕 고도 Kalman 필터 적용
                    enhancedAltitude = applyAltitudeKalmanFilter(
                        rawEnhancedAltitude.toDouble(),
                        location.verticalAccuracyMeters.toDouble()
                    ).toFloat()
                }
            }
        }
    }
    
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
        
        val reading = AccelerometerReading(x, y, z, timestamp)
        accelerometerBuffer.add(reading)
        
        if (accelerometerBuffer.size > maxBufferSize) {
            accelerometerBuffer.removeAt(0)
        }
    }
    
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
        
        val reading = GyroscopeReading(x, y, z, timestamp)
        gyroscopeBuffer.add(reading)
        
        if (gyroscopeBuffer.size > maxBufferSize) {
            gyroscopeBuffer.removeAt(0)
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    // 🆕 Kalman 필터 (고도)
    private fun initAltitudeKalmanFilter(altitude: Double) {
        kalmanAltitude = altitude
        altitudeVariance = 25.0  // 초기 분산 (5m 정확도 가정)
        isAltitudeKalmanInitialized = true
        
        Log.d(TAG, "[KalmanFilter] Altitude initialized: %.2fm".format(altitude))
    }
    
    private fun applyAltitudeKalmanFilter(measuredAltitude: Double, accuracy: Double): Double {
        if (!isAltitudeKalmanInitialized) {
            initAltitudeKalmanFilter(measuredAltitude)
            return measuredAltitude
        }
        
        // 측정 노이즈
        var measurementNoise = accuracy * accuracy
        if (measurementNoise <= 0) {
            measurementNoise = 25.0  // 기본값
        }
        
        // 예측 단계
        val predictedVariance = altitudeVariance + altitudeProcessNoise
        
        // 칼만 게인
        val kalmanGain = predictedVariance / (predictedVariance + measurementNoise)
        
        // 업데이트 단계
        kalmanAltitude = kalmanAltitude + kalmanGain * (measuredAltitude - kalmanAltitude)
        altitudeVariance = (1.0 - kalmanGain) * predictedVariance
        
        return kalmanAltitude
    }
    
    private fun resetAltitudeKalmanFilter() {
        isAltitudeKalmanInitialized = false
        altitudeVariance = 0.0
        Log.d(TAG, "[KalmanFilter] Altitude reset")
    }

    // 🆕 세션 통계 초기화
    private fun resetSessionStats() {
        sessionDistance = 0.0
        sessionElevationGain = 0.0
        sessionElevationLoss = 0.0
        sessionMaxSpeed = 0f
        sessionMovingTime = 0.0
        sessionElapsedTime = 0.0
        sessionStartTime = System.currentTimeMillis()
        previousLocation = null
        previousAltitude = 0.0
        lastUpdateTime = 0
        
        Log.d(TAG, "[Stats] Session reset")
    }
    
    // 🆕 세션 통계 업데이트
    private fun updateSessionStats(location: Location, currentAltitude: Double) {
        val currentTime = location.time
        
        if (previousLocation == null) {
            previousLocation = location
            previousAltitude = currentAltitude
            lastUpdateTime = currentTime
            return
        }
        
        // 1. 거리 계산
        val distance = previousLocation!!.distanceTo(location).toDouble()
        
        // 최소 거리 필터 (노이즈 제거)
        if (distance in 0.5..100.0) {  // 0.5m ~ 100m 사이만 유효
            sessionDistance += distance
        }
        
        // 2. 시간 계산
        val timeDelta = (currentTime - lastUpdateTime) / 1000.0  // 초 단위
        if (timeDelta in 0.0..10.0) {  // 0초 ~ 10초 사이만 유효 (비정상 값 필터)
            // 총 경과 시간
            sessionElapsedTime += timeDelta
            
            // 이동 시간 (속도가 0.5 m/s 이상일 때만)
            if (location.hasSpeed() && location.speed >= 0.5f) {
                sessionMovingTime += timeDelta
            }
        }
        
        // 3. 고도 변화 계산
        val elevationChange = currentAltitude - previousAltitude
        
        // 최소 고도 변화 필터 (0.5m 이상만)
        if (abs(elevationChange) > 0.5) {
            if (elevationChange > 0) {
                sessionElevationGain += elevationChange
            } else {
                sessionElevationLoss += abs(elevationChange)
            }
        }
        
        // 4. 최고 속도 업데이트
        if (location.hasSpeed() && location.speed > sessionMaxSpeed) {
            sessionMaxSpeed = location.speed
        }
        
        // 이전 위치/고도/시간 업데이트
        previousLocation = location
        previousAltitude = currentAltitude
        lastUpdateTime = currentTime
    }
    
    // 🆕 Grade 계산
    private fun calculateGrade(location: Location, currentAltitude: Double): GradeData {
        if (previousLocation == null) {
            return GradeData(0f, "flat")
        }
        
        // 수평 거리
        val horizontalDistance = previousLocation!!.distanceTo(location).toDouble()
        
        // 최소 거리 필터
        if (horizontalDistance < 5.0) {
            return GradeData(0f, "flat")
        }
        
        // 고도 변화
        val elevationChange = currentAltitude - previousAltitude
        
        // Grade 계산 (%)
        var grade = ((elevationChange / horizontalDistance) * 100.0).toFloat()
        
        // 범위 제한 (-30% ~ 30%)
        grade = max(-30f, min(30f, grade))
        
        // 카테고리 결정
        val category = getGradeCategory(grade)
        
        return GradeData(grade, category)
    }
    
    // 🆕 Grade 카테고리
    private fun getGradeCategory(grade: Float): String {
        val absGrade = abs(grade)
        
        return when {
            absGrade < 2.0f -> "flat"
            absGrade < 5.0f -> "gentle"
            absGrade < 8.0f -> "moderate"
            absGrade < 12.0f -> "steep"
            else -> "very_steep"
        }
    }

    private fun generateMotionAnalysis(): MotionAnalysis? {
        if (!advancedTracking || accelerometerBuffer.isEmpty()) {
            return null
        }
        
        val vibrationIntensity = calculateVibrationIntensity()
        val roadSurfaceQuality = when {
            vibrationIntensity < 0.2f -> "smooth"
            vibrationIntensity < 0.5f -> "rough"
            else -> "very_rough"
        }
        
        val corneringIntensity = if (gyroscopeBuffer.isNotEmpty()) {
            val avgRotationZ = gyroscopeBuffer.map { abs(it.z) }.average().toFloat()
            (avgRotationZ / 3.0f).coerceIn(0f, 1f)
        } else {
            0f
        }
        
        val (inclineAngle, isClimbing, isDescending) = calculateIncline()
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
        return ((avgVariation - 0.5f) / 2.5f).coerceIn(0f, 1f)
    }
    
    private fun calculateIncline(): Triple<Float, Boolean, Boolean> {
        if (accelerometerBuffer.isEmpty()) {
            return Triple(0f, false, false)
        }
        
        val avgX = accelerometerBuffer.map { it.x }.average().toFloat()
        val avgY = accelerometerBuffer.map { it.y }.average().toFloat()
        val avgZ = accelerometerBuffer.map { it.z }.average().toFloat()
        
        val pitchAngle = Math.toDegrees(
            kotlin.math.atan2(avgY.toDouble(), avgZ.toDouble())
        ).toFloat()
        
        val isClimbing = pitchAngle > 5f
        val isDescending = pitchAngle < -5f
        
        return Triple(pitchAngle, isClimbing, isDescending)
    }

    private fun initKalmanFilter(location: Location) {
        kalmanLat = location.latitude
        kalmanLng = location.longitude
        variance = (location.accuracy * location.accuracy).toDouble()
        isKalmanInitialized = true
        
        Log.d(TAG, "[KalmanFilter] Position initialized")
    }

    private fun resetKalmanFilter() {
        isKalmanInitialized = false
        variance = 0.0
        Log.d(TAG, "[KalmanFilter] Position reset")
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
                    "Distance: ${String.format("%.2f", sessionDistance)}m\n" +
                    "Elevation +: ${String.format("%.1f", sessionElevationGain)}m\n" +
                    "Speed: ${String.format("%.1f", if (lastLocation!!.hasSpeed()) lastLocation!!.speed * 3.6 else 0f)} km/h"
            
            val motionInfo = if (advancedTracking && accelerometerBuffer.isNotEmpty()) {
                val analysis = generateMotionAnalysis()
                analysis?.let {
                    "\nSurface: ${it.roadSurfaceQuality}\n" +
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
            resetAltitudeKalmanFilter()
            resetSessionStats()  // 🆕 통계 리셋
            
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
                            // 위치 Kalman 필터 적용
                            val processedLocation = if (useKalmanFilter) {
                                applyKalmanFilter(location)
                            } else {
                                location
                            }
                            
                            // 첫 GPS 고도 설정
                            if (startGpsAltitude == null && processedLocation.hasAltitude()) {
                                startGpsAltitude = processedLocation.altitude.toFloat()
                                enhancedAltitude = startGpsAltitude!!
                                
                                // 🆕 고도 Kalman 필터 초기화
                                initAltitudeKalmanFilter(startGpsAltitude!!.toDouble())
                            }
                            
                            // 🆕 사용할 고도 결정
                            val currentAltitude = if (pressureSensor != null && startGpsAltitude != null) {
                                // 기압계 있음 → enhancedAltitude 사용 (이미 Kalman 적용됨)
                                enhancedAltitude.toDouble()
                            } else {
                                // 기압계 없음 → GPS altitude에 Kalman 적용
                                applyAltitudeKalmanFilter(
                                    processedLocation.altitude,
                                    processedLocation.verticalAccuracyMeters.toDouble()
                                )
                            }
                            
                            // 🆕 통계 업데이트
                            updateSessionStats(processedLocation, currentAltitude)
                            
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
        
        // 현재 고도 결정
        val currentAltitude = if (pressureSensor != null && startGpsAltitude != null) {
            enhancedAltitude.toDouble()
        } else {
            kalmanAltitude
        }
        
        // 기압계 데이터
        val barometerData = currentPressure?.let { pressure ->
            BarometerData(
                pressure = pressure,
                relativeAltitude = relativeAltitude,
                enhancedAltitude = enhancedAltitude
            )
        }
        
        // 가속계 데이터
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
        
        // 자이로스코프 데이터
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
        
        // 운동 분석 데이터
        val motionAnalysis = if (advancedTracking) {
            generateMotionAnalysis()
        } else null
        
        // 🆕 Grade 계산
        val gradeData = calculateGrade(location, currentAltitude)
        
        // 🆕 세션 통계
        val sessionStats = SessionStats(
            distance = sessionDistance,
            elevationGain = sessionElevationGain,
            elevationLoss = sessionElevationLoss,
            movingTime = sessionMovingTime,
            elapsedTime = sessionElapsedTime,
            maxSpeed = sessionMaxSpeed,
            avgSpeed = if (sessionElapsedTime > 0) sessionDistance / sessionElapsedTime else 0.0,
            movingAvgSpeed = if (sessionMovingTime > 0) sessionDistance / sessionMovingTime else 0.0
        )
        
        val sensorData = SensorData(
            barometer = barometerData,
            accelerometer = accelerometerData,
            gyroscope = gyroscopeData,
            motionAnalysis = motionAnalysis,
            grade = gradeData,              // 🆕 Grade
            sessionStats = sessionStats     // 🆕 통계
        )
        
        locationListener?.invoke(location, sensorData)
        updateNotification()
    }

    fun stopForegroundTracking() {
        Log.d(TAG, "🛑 Stopping GPS tracking")
        
        // 🆕 최종 통계 로그
        Log.d(TAG, "[Stats] Final - Distance: %.2fm, Elevation Gain: %.2fm, Loss: %.2fm, Max Speed: %.2fm/s, Moving Time: %.0fs, Elapsed Time: %.0fs"
            .format(sessionDistance, sessionElevationGain, sessionElevationLoss, sessionMaxSpeed, sessionMovingTime, sessionElapsedTime))
        
        stopRepeatLocationUpdates()
        
        locationCallback?.let { callback ->
            fusedLocationClient?.removeLocationUpdates(callback)
        }
        locationCallback = null
        
        stopSensors()
        resetKalmanFilter()
        resetAltitudeKalmanFilter()
        
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
        // 현재 고도 결정
        val currentAltitude = if (pressureSensor != null && startGpsAltitude != null) {
            enhancedAltitude.toDouble()
        } else {
            kalmanAltitude
        }
        
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
        
        // 🆕 Grade 계산
        val gradeData = lastLocation?.let { location ->
            calculateGrade(location, currentAltitude)
        }
        
        // 🆕 세션 통계
        val sessionStats = SessionStats(
            distance = sessionDistance,
            elevationGain = sessionElevationGain,
            elevationLoss = sessionElevationLoss,
            movingTime = sessionMovingTime,
            elapsedTime = sessionElapsedTime,
            maxSpeed = sessionMaxSpeed,
            avgSpeed = if (sessionElapsedTime > 0) sessionDistance / sessionElapsedTime else 0.0,
            movingAvgSpeed = if (sessionMovingTime > 0) sessionDistance / sessionMovingTime else 0.0
        )
        
        return SensorData(
            barometerData, 
            accelerometerData, 
            gyroscopeData, 
            motionAnalysis,
            gradeData,
            sessionStats
        )
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