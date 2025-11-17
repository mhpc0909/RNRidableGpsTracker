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
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

class LocationService : Service(), SensorEventListener {

    private val binder = LocalBinder()
    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var lastLocation: Location? = null
    private var locationListener: ((Location, SensorData?) -> Unit)? = null
    private var isForegroundStarted = false
    private var isNewLocationAvailable = false
    private val singleLocationHandler = Handler(Looper.getMainLooper())
    private var pendingSingleLocationCallback: LocationCallback? = null
    private var singleLocationTimeoutRunnable: Runnable? = null
    
    // 센서 관련
    private var sensorManager: SensorManager? = null
    private var pressureSensor: Sensor? = null
    private var accelerometerSensor: Sensor? = null
    private var gyroscopeSensor: Sensor? = null
    private var magnetometerSensor: Sensor? = null
    private var lightSensor: Sensor? = null
    
    // 오디오 관련 (소음 측정)
    private var audioRecorder: AudioRecord? = null
    private var isRecordingNoise = false
    private val noiseHandler = Handler(Looper.getMainLooper())
    
    // 기압계 관련
    private var referencePressure: Float? = null
    private var currentPressure: Float? = null
    private var relativeAltitude: Float = 0f
    private var startGpsAltitude: Float? = null
    private var enhancedAltitude: Float = 0f
    
    // 가속계 관련
    private var lastAccelerometerData: FloatArray = FloatArray(3)
    private var accelerometerTimestamp: Long = 0
    private val accelerometerBuffer = mutableListOf<AccelerometerReading>()
    private val maxBufferSize = 10
    
    // 자이로스코프 관련
    private var lastGyroscopeData: FloatArray = FloatArray(3)
    private var gyroscopeTimestamp: Long = 0
    private val gyroscopeBuffer = mutableListOf<GyroscopeReading>()
    
    // 자기장 센서 관련
    private var lastMagnetometerData: FloatArray = FloatArray(3)
    private var magnetometerTimestamp: Long = 0
    private var magnetometerHeading: Float = 0f
    
    // 광센서 관련
    private var currentLux: Float = 0f
    private var lastLuxTimestamp: Long = 0
    
    // 소음 관련
    private var currentDecibel: Float = 0f
    private var lastDecibelTimestamp: Long = 0
    
    // Kalman 필터 (위치)
    private var kalmanLat: Double = 0.0
    private var kalmanLng: Double = 0.0
    private var variance: Double = 0.0
    private var isKalmanInitialized = false
    
    // Kalman 필터 (고도)
    private var kalmanAltitude: Double = 0.0
    private var altitudeVariance: Double = 0.0
    private var isAltitudeKalmanInitialized = false
    private var altitudeProcessNoise: Double = 3.0
    
    // 운동 타입별 필터 파라미터
    private var processNoise: Double = 0.0
    private var useKalmanFilter: Boolean = false
    private var exerciseType: String = "bicycle"
    
    // 센서 개별 제어
    private var useAccelerometer: Boolean = true
    private var useGyroscope: Boolean = true
    private var useMagnetometer: Boolean = false
    private var useLight: Boolean = true
    private var useNoise: Boolean = false
    
    // 통계 데이터
    private var sessionDistance: Double = 0.0
    private var sessionElevationGain: Double = 0.0
    private var sessionElevationLoss: Double = 0.0
    private var sessionMaxSpeed: Float = 0f
    private var sessionMovingTime: Double = 0.0
    private var sessionElapsedTime: Double = 0.0
    private var sessionStartTime: Long = 0
    private var previousLocation: Location? = null
    private var previousAltitude: Double = 0.0
    private var lastUpdateTime: Long = 0
    private var isCurrentlyMoving: Boolean = false
    private var currentFilteredSpeed: Double = 0.0
    private var lastElapsedUpdateTime: Long = 0
    private var lastMovingUpdateTime: Long = 0
    private var gradeBaseLocation: Location? = null
    private var gradeBaseAltitude: Double = 0.0
    private val recentGrades = mutableListOf<Double>()
    private var lastSmoothedGrade: Double = 0.0
    private var stationaryGradeCounter: Int = 0
    private var lastRawLatitude: Double? = null
    private var lastRawLongitude: Double? = null
    private var lastRawAltitude: Double? = null
    
    // Pause 관련 상태
    private var isPaused: Boolean = false
    private var pauseStartTime: Long = 0
    private var pausedPreviousLocation: Location? = null
    private var pausedPreviousAltitude: Double = 0.0
    private var skipNextDistanceUpdate: Boolean = false  // Resume 후 첫 번째 거리 계산 건너뛰기
    
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
        private const val MOVEMENT_SPEED_THRESHOLD = 0.5
        private const val MOVEMENT_HYSTERESIS = 0.2
        private const val MIN_MOVEMENT_DISTANCE = 0.5
        private const val MAX_MOVEMENT_DISTANCE = 100.0
        private const val MAX_MOVING_TIME_DELTA = 10.0
        private const val GRADE_DISTANCE_THRESHOLD = 5.0
        private const val GRADE_WINDOW_SIZE = 3
        private const val GRADE_DISTANCE_PER_SPEED = 1.0  // meters of travel per 1 m/s before recalculating grade
        private const val GRADE_MIN_SPEED_THRESHOLD = 1.5 // m/s; below this, grade updates are limited
        private const val GRADE_MAX_DELTA_SLOW = 3.0  // % change allowed when very slow
        private const val GRADE_MAX_DELTA_MEDIUM = 6.0 // % change allowed at medium speed
        private const val GRADE_MAX_DELTA_FAST = 10.0 // % change allowed at higher speed
        private const val STATIONARY_GRADE_RESET_THRESHOLD = 2
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
        val roadSurfaceQuality: String,        // "smooth", "rough", "very_rough"
        val vibrationLevel: Float,             // 원본 진동 수치 (0.0 ~ 10.0+)
        val vibrationIntensity: Float,         // 정규화된 진동 강도 (0.0 ~ 1.0)
        val corneringIntensity: Float,
        val inclineAngle: Float,
        val isClimbing: Boolean,
        val isDescending: Boolean,
        val verticalAcceleration: Float
    )
    
    data class GradeData(
        val grade: Float,
        val gradeCategory: String
    )
    
    data class SessionStats(
        val distance: Double,
        val elevationGain: Double,
        val elevationLoss: Double,
        val movingTime: Double,
        val elapsedTime: Double,
        val maxSpeed: Float,
        val avgSpeed: Double,
        val movingAvgSpeed: Double
    )
    
    data class SensorData(
        val barometer: BarometerData?,
        val motionAnalysis: MotionAnalysis?,
        val grade: GradeData?,
        val sessionStats: SessionStats?,
        val light: LightData?,
        val noise: NoiseData?,
        val magnetometer: MagnetometerData?
    )
    
    data class LightData(
        val lux: Float,
        val condition: String,
        val isLowLight: Boolean
    )
    
    data class NoiseData(
        val decibel: Float,
        val noiseLevel: String
    )
    
    data class MagnetometerData(
        val heading: Float,
        val magneticFieldStrength: Float,
        val x: Float,
        val y: Float,
        val z: Float
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
        
        magnetometerSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
        if (magnetometerSensor != null) {
            Log.d(TAG, "✅ Magnetometer available: ${magnetometerSensor!!.name}")
        }
        
        lightSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_LIGHT)
        if (lightSensor != null) {
            Log.d(TAG, "✅ Light sensor available: ${lightSensor!!.name}")
        }
    }

    private fun startSensors() {
        // 기압계 (항상 사용)
        pressureSensor?.let { sensor ->
            sensorManager?.registerListener(
                this,
                sensor,
                SensorManager.SENSOR_DELAY_NORMAL
            )
            Log.d(TAG, "📊 Barometer started")
        }
        
        // 광센서 (useLight)
        if (useLight) {
            lightSensor?.let { sensor ->
                sensorManager?.registerListener(
                    this,
                    sensor,
                    1_000_000  // 1Hz
                )
                Log.d(TAG, "💡 Light sensor started (1 Hz)")
            }
        }
        
        // 가속계 (useAccelerometer)
        if (useAccelerometer) {
            accelerometerSensor?.let { sensor ->
                sensorManager?.registerListener(
                    this,
                    sensor,
                    SensorManager.SENSOR_DELAY_GAME  // 50Hz
                )
                Log.d(TAG, "📊 Accelerometer started (50 Hz)")
            }
        }
        
        // 자이로스코프 (useGyroscope)
        if (useGyroscope) {
            gyroscopeSensor?.let { sensor ->
                sensorManager?.registerListener(
                    this,
                    sensor,
                    SensorManager.SENSOR_DELAY_GAME  // 50Hz
                )
                Log.d(TAG, "📊 Gyroscope started (50 Hz)")
            }
        }
        
        // 자기장 센서 (useMagnetometer)
        if (useMagnetometer) {
            magnetometerSensor?.let { sensor ->
                val registered = sensorManager?.registerListener(
                    this,
                    sensor,
                    1_000_000  // 1Hz
                )
                Log.d(TAG, "🧭 Magnetometer start: registered=$registered, sensor=${sensor.name}")
            } ?: run {
                Log.e(TAG, "❌ Magnetometer sensor is NULL!")
            }
        } else {
            Log.d(TAG, "⚠️ Magnetometer disabled by configuration")
        }
        
        // 소음 측정 (useNoise)
        if (useNoise) {
            startNoiseMeasurement()
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
        
        // 자기장 센서 초기화
        lastMagnetometerData = FloatArray(3)
        magnetometerHeading = 0f
        magnetometerTimestamp = 0
        
        currentLux = 0f
        lastLuxTimestamp = 0
        
        currentDecibel = 0f
        lastDecibelTimestamp = 0
        
        stopNoiseMeasurement()
        resetGradeTracking()
        stationaryGradeCounter = 0
        lastRawLatitude = null
        lastRawLongitude = null
        lastRawAltitude = null
        
        Log.d(TAG, "📊 All sensors stopped")
    }

    override fun onSensorChanged(event: SensorEvent?) {
        if (event == null) return
        
        when (event.sensor.type) {
            Sensor.TYPE_PRESSURE -> handlePressureData(event)
            Sensor.TYPE_ACCELEROMETER -> handleAccelerometerData(event)
            Sensor.TYPE_GYROSCOPE -> handleGyroscopeData(event)
            Sensor.TYPE_MAGNETIC_FIELD -> handleMagnetometerData(event)
            Sensor.TYPE_LIGHT -> handleLightData(event)
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
                    
                    val rawEnhancedAltitude = (gpsAlt * 0.3f) + (baroAltitude * 0.7f)
                    
                    enhancedAltitude = applyAltitudeKalmanFilter(
                        rawEnhancedAltitude.toDouble(),
                        location.verticalAccuracyMeters.toDouble()
                    ).toFloat()
                }
            }
        }
    }
    
    private fun handleAccelerometerData(event: SensorEvent) {
        if (!useAccelerometer) return
        
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
        if (!useGyroscope) return
        
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
    
    private fun handleMagnetometerData(event: SensorEvent) {
        if (!useMagnetometer) {
            Log.d(TAG, "⚠️ Magnetometer disabled, skipping data")
            return
        }
        
        val x = event.values[0]
        val y = event.values[1]
        val z = event.values[2]
        val timestamp = System.currentTimeMillis()
        
        lastMagnetometerData[0] = x
        lastMagnetometerData[1] = y
        lastMagnetometerData[2] = z
        magnetometerTimestamp = timestamp
        
        val heading = Math.toDegrees(kotlin.math.atan2(y.toDouble(), x.toDouble())).toFloat()
        magnetometerHeading = if (heading < 0) heading + 360f else heading
        
        val strength = calculateMagneticFieldStrength(x, y, z)
        Log.d(TAG, "🧭 Magnetometer: heading=%.1f°, strength=%.2fμT, x=%.2f, y=%.2f, z=%.2f"
            .format(magnetometerHeading, strength, x, y, z))
    }
    
    private fun calculateMagneticFieldStrength(x: Float, y: Float, z: Float): Float {
        return sqrt(x * x + y * y + z * z)
    }
    
    private fun handleLightData(event: SensorEvent) {
        currentLux = event.values[0]
        lastLuxTimestamp = System.currentTimeMillis()
    }
    
    private fun startNoiseMeasurement() {
        if (isRecordingNoise) {
            Log.d(TAG, "⚠️ Noise measurement already running")
            return
        }
        
        isRecordingNoise = true
        
        // AudioRecord를 한 번만 생성하고 재사용
        try {
            val bufferSize = AudioRecord.getMinBufferSize(
                8000, // 44100 -> 8000 Hz로 낮춤 (소음 측정에는 충분)
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            
            if (bufferSize == AudioRecord.ERROR || bufferSize == AudioRecord.ERROR_BAD_VALUE) {
                Log.e(TAG, "❌ AudioRecord buffer size error")
                isRecordingNoise = false
                return
            }
            
            audioRecorder = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                8000, // 낮은 샘플레이트
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT,
                bufferSize
            )
            
            if (audioRecorder?.state != AudioRecord.STATE_INITIALIZED) {
                Log.e(TAG, "❌ AudioRecord not initialized (권한 문제 가능성)")
                audioRecorder?.release()
                audioRecorder = null
                isRecordingNoise = false
                return
            }
            
            audioRecorder?.startRecording()
        } catch (e: SecurityException) {
            Log.e(TAG, "❌ 마이크 권한 없음 (RECORD_AUDIO 권한 필요)", e)
            isRecordingNoise = false
            return
        } catch (e: Exception) {
            Log.e(TAG, "❌ AudioRecord 생성 실패", e)
            isRecordingNoise = false
            return
        }
        
        // 백그라운드 스레드에서 측정
        val noiseRunnable = object : Runnable {
            override fun run() {
                if (!isRecordingNoise) return
                
                try {
                    val decibel = measureNoiseLevel()
                    if (decibel > 0) {
                        currentDecibel = decibel
                        lastDecibelTimestamp = System.currentTimeMillis()
                        Log.d(TAG, "🎤 Noise: %.1f dB".format(decibel))
                    } else {
                        Log.w(TAG, "⚠️ Noise measurement returned 0")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 소음 측정 오류", e)
                }
                
                if (isRecordingNoise) {
                    noiseHandler.postDelayed(this, 1000L)
                }
            }
        }
        
        // 백그라운드 스레드에서 실행
        Thread {
            noiseHandler.post(noiseRunnable)
        }.start()
        
        Log.d(TAG, "🎤 Noise measurement started (1 Hz)")
    }
    
    private fun stopNoiseMeasurement() {
        isRecordingNoise = false
        noiseHandler.removeCallbacksAndMessages(null)
        
        // AudioRecord 정리
        try {
            audioRecorder?.stop()
            audioRecorder?.release()
        } catch (e: Exception) {
            Log.e(TAG, "❌ AudioRecord 정리 오류", e)
        }
        audioRecorder = null
        
        currentDecibel = 0f
        lastDecibelTimestamp = 0
        Log.d(TAG, "🎤 Noise measurement stopped")
    }
    
    private fun measureNoiseLevel(): Float {
        val recorder = audioRecorder ?: return 0f
        
        try {
            val bufferSize = AudioRecord.getMinBufferSize(
                8000,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            
            if (bufferSize == AudioRecord.ERROR || bufferSize == AudioRecord.ERROR_BAD_VALUE) {
                return 0f
            }
            
            // 작은 버퍼 사용 (더 빠른 처리)
            val buffer = ShortArray(bufferSize / 4) // 버퍼 크기 1/4로 감소
            val readSize = recorder.read(buffer, 0, buffer.size)
            
            if (readSize > 0) {
                // 최적화된 RMS 계산
                var sum = 0.0
                var count = 0
                for (i in 0 until readSize) {
                    val value = buffer[i].toDouble()
                    sum += value * value
                    count++
                }
                
                if (count > 0) {
                    val rms = sqrt(sum / count)
                    
                    // RMS를 데시벨로 변환
                    val referenceAmplitude = 32767.0
                    val decibel = 20 * log10(rms / referenceAmplitude)
                    
                    // 0~120 dB 범위로 정규화
                    return max(0f, min(120f, (decibel + 120).toFloat()))
                }
            }
            
            return 0f
        } catch (e: Exception) {
            Log.e(TAG, "❌ 소음 측정 실패", e)
            return 0f
        }
    }
    private fun getLightCondition(lux: Float): String {
        return when {
            lux < 10 -> "dark"
            lux < 50 -> "dim"
            lux < 200 -> "indoor"
            lux < 1000 -> "overcast"
            lux < 10000 -> "daylight"
            else -> "bright_sunlight"
        }
    }
    
    private fun getNoiseLevel(decibel: Float): String {
        return when {
            decibel < 30 -> "very_quiet"
            decibel < 50 -> "quiet"
            decibel < 60 -> "moderate"
            decibel < 70 -> "noisy"
            decibel < 85 -> "very_noisy"
            else -> "dangerously_loud"
        }
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {}

    private fun initAltitudeKalmanFilter(altitude: Double) {
        kalmanAltitude = altitude
        altitudeVariance = 25.0
        isAltitudeKalmanInitialized = true
        
        Log.d(TAG, "[KalmanFilter] Altitude initialized: %.2fm".format(altitude))
    }
    
    private fun applyAltitudeKalmanFilter(measuredAltitude: Double, accuracy: Double): Double {
        if (!isAltitudeKalmanInitialized) {
            initAltitudeKalmanFilter(measuredAltitude)
            return measuredAltitude
        }
        
        var measurementNoise = accuracy * accuracy
        if (measurementNoise <= 0) {
            measurementNoise = 25.0
        }
        
        val predictedVariance = altitudeVariance + altitudeProcessNoise
        val kalmanGain = predictedVariance / (predictedVariance + measurementNoise)
        
        kalmanAltitude = kalmanAltitude + kalmanGain * (measuredAltitude - kalmanAltitude)
        altitudeVariance = (1.0 - kalmanGain) * predictedVariance
        
        return kalmanAltitude
    }
    
    private fun resetAltitudeKalmanFilter() {
        isAltitudeKalmanInitialized = false
        altitudeVariance = 0.0
        Log.d(TAG, "[KalmanFilter] Altitude reset")
    }

    private fun resetSessionStats() {
        sessionDistance = 0.0
        sessionElevationGain = 0.0
        sessionElevationLoss = 0.0
        sessionMaxSpeed = 0f
        sessionMovingTime = 0.0
        sessionElapsedTime = 0.0
        sessionStartTime = SystemClock.elapsedRealtime()
        lastElapsedUpdateTime = sessionStartTime
        lastMovingUpdateTime = sessionStartTime
        resetGradeTracking()
        stationaryGradeCounter = 0
        previousLocation = null
        previousAltitude = 0.0
        lastUpdateTime = 0
        isCurrentlyMoving = false
        currentFilteredSpeed = 0.0
        lastRawLatitude = null
        lastRawLongitude = null
        lastRawAltitude = null
        
        // Pause 상태 초기화
        isPaused = false
        pauseStartTime = 0
        pausedPreviousLocation = null
        pausedPreviousAltitude = 0.0
        skipNextDistanceUpdate = false
        
        Log.d(TAG, "[Stats] Session reset")
    }
    
    private fun updateSessionStats(location: Location, currentAltitude: Double) {
        // Pause 중이면 통계 업데이트 안 함 (위치 트래킹은 지속)
        if (isPaused) {
            return
        }
        
        val systemElapsed = SystemClock.elapsedRealtime()
        updateElapsedTimeWithMillis(systemElapsed)
        
        val locationTime = location.time
        
        if (previousLocation == null) {
            previousLocation = location
            previousAltitude = currentAltitude
            lastUpdateTime = locationTime
            lastMovingUpdateTime = systemElapsed
            gradeBaseLocation = location
            gradeBaseAltitude = currentAltitude
            recentGrades.clear()
            lastSmoothedGrade = 0.0
            return
        }
        
        // Resume 후 첫 번째 GPS 업데이트는 거리 계산 건너뛰기
        // (pause 시점 위치와 resume 후 위치 사이의 거리는 포함하지 않음)
        if (skipNextDistanceUpdate) {
            skipNextDistanceUpdate = false
            // previousLocation을 현재 위치로 업데이트 (거리 계산 없이)
            previousLocation = Location(location)
            previousAltitude = currentAltitude
            lastUpdateTime = locationTime
            lastMovingUpdateTime = systemElapsed
            // Grade 기준점도 현재 위치로 재설정
            gradeBaseLocation = Location(location)
            gradeBaseAltitude = currentAltitude
            recentGrades.clear()
            lastSmoothedGrade = 0.0
            Log.d(TAG, "[Resume] Skipped first distance update after resume")
            return
        }
        
        val distance = previousLocation!!.distanceTo(location).toDouble()
        
        // Mock location의 경우 타임스탬프가 동일할 수 있으므로 실제 수신 시간 사용
        val currentTime = System.currentTimeMillis()
        var timeDelta = (locationTime - lastUpdateTime) / 1000.0
        
        // 타임스탬프가 동일하거나 유효하지 않은 경우 최소값 보장
        if (timeDelta <= 0) {
            timeDelta = 0.1
        }
        
        val hasSpeed = location.hasSpeed() && !location.speed.isNaN()
        val rawSpeed = if (hasSpeed) location.speed.toDouble() else 0.0
        
        val distanceWithinBounds = distance >= MIN_MOVEMENT_DISTANCE && distance <= MAX_MOVEMENT_DISTANCE
        val derivedSpeed = if (distanceWithinBounds && timeDelta > 0) distance / timeDelta else 0.0
        var distanceSuggestsMovement = distanceWithinBounds && derivedSpeed >= MOVEMENT_SPEED_THRESHOLD
        
        // 속도 정보가 있고 임계값 이상이면 이동 중으로 판단
        // 거리가 0이어도 속도 정보가 있으면 사용 (Mock location 대응)
        val speedSuggestsMovement = hasSpeed && rawSpeed >= MOVEMENT_SPEED_THRESHOLD
        
        var moving = distanceSuggestsMovement || speedSuggestsMovement
        
        if (!moving && isCurrentlyMoving) {
            val distanceWithinHysteresis = distance >= MIN_MOVEMENT_DISTANCE * 0.4 && distance <= MAX_MOVEMENT_DISTANCE
            val hysteresisSatisfied = distanceWithinHysteresis &&
                ((hasSpeed && rawSpeed >= MOVEMENT_SPEED_THRESHOLD - MOVEMENT_HYSTERESIS) ||
                 (derivedSpeed >= MOVEMENT_SPEED_THRESHOLD - MOVEMENT_HYSTERESIS))
            if (hysteresisSatisfied) {
                moving = true
                distanceSuggestsMovement = true
            }
        }
        
        if (distanceWithinBounds) {
            sessionDistance += distance
        }
        
        if (timeDelta in 0.0..10.0) {
            if (moving) {
                val movingDelta = (systemElapsed - lastMovingUpdateTime) / 1000.0
                if (movingDelta > 0 && movingDelta < MAX_MOVING_TIME_DELTA) {
                    sessionMovingTime += movingDelta
                }
                lastMovingUpdateTime = systemElapsed
            } else {
                lastMovingUpdateTime = systemElapsed
            }
        }
        
        currentFilteredSpeed = if (moving) {
            // 속도 정보가 있으면 우선 사용 (Mock location 대응)
            if (hasSpeed && rawSpeed > 0) {
                max(rawSpeed, derivedSpeed)
            } else {
                derivedSpeed
            }
        } else {
            0.0
        }
        
        val elevationChange = currentAltitude - previousAltitude
        
        // ✅ 거리 조건 제거: 상승/하강은 실제 고도 변화를 반영해야 함
        // ✅ 임계값을 0.1m로 낮춤 (Kalman 필터로 부드러워진 고도 변화도 감지)
        if (abs(elevationChange) > 0.1) {
            if (elevationChange > 0) {
                sessionElevationGain += elevationChange
                Log.d(TAG, "[Elevation] Gain: +${String.format("%.2f", elevationChange)}m (current: ${String.format("%.2f", currentAltitude)}, previous: ${String.format("%.2f", previousAltitude)})")
            } else {
                sessionElevationLoss += abs(elevationChange)
                Log.d(TAG, "[Elevation] Loss: -${String.format("%.2f", abs(elevationChange))}m (current: ${String.format("%.2f", currentAltitude)}, previous: ${String.format("%.2f", previousAltitude)})")
            }
        }
        
        if (currentFilteredSpeed > sessionMaxSpeed) {
            sessionMaxSpeed = currentFilteredSpeed.toFloat()
        }
        
        previousLocation = location
        previousAltitude = currentAltitude
        lastUpdateTime = locationTime
        isCurrentlyMoving = moving
    }
    
    private fun updateElapsedTimeWithMillis(timestampMillis: Long) {
        if (sessionStartTime <= 0) return
        
        if (lastElapsedUpdateTime <= 0) {
            lastElapsedUpdateTime = sessionStartTime
        }
        
        if (timestampMillis < lastElapsedUpdateTime) {
            lastElapsedUpdateTime = timestampMillis
            return
        }
        
        val deltaMillis = timestampMillis - lastElapsedUpdateTime
        if (deltaMillis > 0) {
            sessionElapsedTime += deltaMillis / 1000.0
            lastElapsedUpdateTime = timestampMillis
        }
    }
    
    private fun calculateGrade(location: Location, currentAltitude: Double): GradeData {
        val baseLocation = gradeBaseLocation ?: run {
            gradeBaseLocation = location
            gradeBaseAltitude = currentAltitude
            recentGrades.clear()
            lastSmoothedGrade = 0.0
            return GradeData(0f, "flat")
        }
        
        val horizontalDistance = baseLocation.distanceTo(location).toDouble()
        val speed = max(0.0, currentFilteredSpeed)
        val dynamicThreshold = max(GRADE_DISTANCE_THRESHOLD, speed * GRADE_DISTANCE_PER_SPEED)
        
        if (horizontalDistance < dynamicThreshold) {
            val gradeValue = lastSmoothedGrade.toFloat()
            return GradeData(gradeValue, getGradeCategory(gradeValue))
        }
        
        if (horizontalDistance > MAX_MOVEMENT_DISTANCE) {
            gradeBaseLocation = location
            gradeBaseAltitude = currentAltitude
            recentGrades.clear()
            lastSmoothedGrade = 0.0
            return GradeData(0f, "flat")
        }
        
        val elevationChange = currentAltitude - gradeBaseAltitude
        var rawGrade = (elevationChange / horizontalDistance) * 100.0
        rawGrade = rawGrade.coerceIn(-30.0, 30.0)
        
        // 속도에 따라 허용하는 경사 변화량을 다르게 설정
        val delta = rawGrade - lastSmoothedGrade
        val maxDelta = when {
            speed < GRADE_MIN_SPEED_THRESHOLD -> GRADE_MAX_DELTA_SLOW
            speed < 5.0 -> GRADE_MAX_DELTA_MEDIUM
            else -> GRADE_MAX_DELTA_FAST
        }
        val limitedDelta = delta.coerceIn(-maxDelta, maxDelta)
        rawGrade = lastSmoothedGrade + limitedDelta
        
        recentGrades.add(rawGrade)
        if (recentGrades.size > GRADE_WINDOW_SIZE) {
            recentGrades.removeAt(0)
        }
        
        lastSmoothedGrade = if (recentGrades.isNotEmpty()) {
            recentGrades.sum() / recentGrades.size
        } else {
            0.0
        }
        
        gradeBaseLocation = location
        gradeBaseAltitude = currentAltitude
        
        val gradeValue = lastSmoothedGrade.toFloat()
        return GradeData(gradeValue, getGradeCategory(gradeValue))
    }
    
    private fun resolveGradeData(
        location: Location,
        currentAltitude: Double,
        moving: Boolean,
        updateStationaryState: Boolean
    ): GradeData {
        val shouldZeroGrade = handleStationaryGradeState(
            location,
            currentAltitude,
            moving,
            updateStationaryState
        )
        return if (shouldZeroGrade) {
            GradeData(0f, "flat")
        } else {
            calculateGrade(location, currentAltitude)
        }
    }

    private fun handleStationaryGradeState(
        location: Location,
        currentAltitude: Double,
        moving: Boolean,
        updateStationaryState: Boolean
    ): Boolean {
        if (moving) {
            if (updateStationaryState) {
                stationaryGradeCounter = 0
            }
            return false
        }

        if (updateStationaryState && stationaryGradeCounter < STATIONARY_GRADE_RESET_THRESHOLD) {
            stationaryGradeCounter++
        }

        val shouldZero = stationaryGradeCounter >= STATIONARY_GRADE_RESET_THRESHOLD
        if (shouldZero) {
            resetGradeTracking(location, currentAltitude)
        }

        return shouldZero
    }

    private fun resetGradeTracking(location: Location? = null, currentAltitude: Double? = null) {
        gradeBaseLocation = location?.let { Location(it) }
        gradeBaseAltitude = currentAltitude ?: 0.0
        recentGrades.clear()
        lastSmoothedGrade = 0.0
    }
    
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
        // 가속계나 자이로스코프 중 하나라도 사용하지 않으면 null
        if (!useAccelerometer && !useGyroscope) {
            return null
        }
        
        // 가속계 사용 시 진동 데이터 계산
        val vibrationLevel: Float
        val vibrationIntensity: Float
        val roadSurfaceQuality: String
        val inclineAngle: Float
        val isClimbing: Boolean
        val isDescending: Boolean
        val verticalAcceleration: Float
        
        if (useAccelerometer && accelerometerBuffer.isNotEmpty()) {
            // 원본 진동 수치 계산
            vibrationLevel = calculateVibrationLevel()
            
            // 정규화된 진동 강도 (0.0 ~ 1.0)
            vibrationIntensity = calculateVibrationIntensity()
            
            // 노면 품질 분류
            roadSurfaceQuality = when {
                vibrationIntensity < 0.2f -> "smooth"
                vibrationIntensity < 0.5f -> "rough"
                else -> "very_rough"
            }
            
            val inclineData = calculateIncline()
            inclineAngle = inclineData.first
            isClimbing = inclineData.second
            isDescending = inclineData.third
            verticalAcceleration = lastAccelerometerData[2] - GRAVITY
        } else {
            vibrationLevel = 0f
            vibrationIntensity = 0f
            roadSurfaceQuality = "smooth"
            inclineAngle = 0f
            isClimbing = false
            isDescending = false
            verticalAcceleration = 0f
        }
        
        // 자이로스코프 사용 시 코너링 데이터 계산
        val corneringIntensity = if (useGyroscope && gyroscopeBuffer.isNotEmpty()) {
            val avgRotationZ = gyroscopeBuffer.map { abs(it.z) }.average().toFloat()
            (avgRotationZ / 3.0f).coerceIn(0f, 1f)
        } else {
            0f
        }
        
        return MotionAnalysis(
            roadSurfaceQuality = roadSurfaceQuality,
            vibrationLevel = vibrationLevel,
            vibrationIntensity = vibrationIntensity,
            corneringIntensity = corneringIntensity,
            inclineAngle = inclineAngle,
            isClimbing = isClimbing,
            isDescending = isDescending,
            verticalAcceleration = verticalAcceleration
        )
    }
    
    private fun calculateVibrationLevel(): Float {
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
        
        // 원본 평균 변화량 반환 (m/s²)
        return totalVariation / (accelerometerBuffer.size - 1)
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
        val sensorStatus = buildString {
            append("Sensors[")
            if (useAccelerometer) append("A ")
            if (useGyroscope) append("G ")
            if (useMagnetometer) append("M ")
            if (useLight) append("L ")
            if (useNoise) append("N")
            append("]")
        }
        
        val locationText = if (lastLocation != null) {
            val pauseStatus = if (isPaused) " (Paused)" else ""
            val baseInfo = "Exercise: $exerciseType (K:$kalmanStatus)$pauseStatus\n" +
                    "$sensorStatus\n" +
                    "Distance: ${String.format("%.2f", sessionDistance)}m\n" +
                    "Elevation +: ${String.format("%.1f", sessionElevationGain)}m\n" +
                    "Speed: ${String.format("%.1f", if (lastLocation!!.hasSpeed()) lastLocation!!.speed * 3.6 else 0f)} km/h"
            
            val motionInfo = if (useAccelerometer && accelerometerBuffer.isNotEmpty()) {
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
        useAccelerometer: Boolean = true,
        useGyroscope: Boolean = true,
        useMagnetometer: Boolean = false,
        useLight: Boolean = true,
        useNoise: Boolean = false
    ) {
        this.distanceFilter = distanceFilter
        this.updateInterval = interval
        this.fastestInterval = fastestInterval
        this.exerciseType = exerciseType
        this.useAccelerometer = useAccelerometer
        this.useGyroscope = useGyroscope
        this.useMagnetometer = useMagnetometer
        this.useLight = useLight
        this.useNoise = useNoise
        
        when (exerciseType) {
            "bicycle" -> {
                this.priority = Priority.PRIORITY_HIGH_ACCURACY
                this.useKalmanFilter = false
                this.processNoise = 0.0
                Log.d(TAG, "🚴 Bicycle mode: Kalman=$useKalmanFilter, Sensors=[A:$useAccelerometer G:$useGyroscope M:$useMagnetometer L:$useLight N:$useNoise]")
            }
            "running" -> {
                this.priority = Priority.PRIORITY_HIGH_ACCURACY
                this.useKalmanFilter = true
                this.processNoise = 7.0
                Log.d(TAG, "🏃 Running mode: Kalman=$useKalmanFilter, Sensors=[A:$useAccelerometer G:$useGyroscope M:$useMagnetometer L:$useLight N:$useNoise]")
            }
            "hiking" -> {
                this.priority = Priority.PRIORITY_HIGH_ACCURACY
                this.useKalmanFilter = true
                this.processNoise = 1.0
                Log.d(TAG, "🥾 Hiking mode: Kalman=$useKalmanFilter, Sensors=[A:$useAccelerometer G:$useGyroscope M:$useMagnetometer L:$useLight N:$useNoise]")
            }
            "walking" -> {
                this.priority = Priority.PRIORITY_HIGH_ACCURACY
                this.useKalmanFilter = true
                this.processNoise = 1.0
                Log.d(TAG, "🚶 Walking mode: Kalman=$useKalmanFilter, Sensors=[A:$useAccelerometer G:$useGyroscope M:$useMagnetometer L:$useLight N:$useNoise]")
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
            Log.d(TAG, "🚀 Starting GPS tracking: $exerciseType")
            
            locationCallback?.let { callback ->
                fusedLocationClient?.removeLocationUpdates(callback)
            }
            
            resetKalmanFilter()
            resetAltitudeKalmanFilter()
            resetSessionStats()
            
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
                            lastRawLatitude = location.latitude
                            lastRawLongitude = location.longitude
                            lastRawAltitude = if (location.hasAltitude()) {
                                location.altitude
                            } else {
                                null
                            }

                            val processedLocation = if (useKalmanFilter) {
                                applyKalmanFilter(location)
                            } else {
                                location
                            }
                            
                            if (startGpsAltitude == null && processedLocation.hasAltitude()) {
                                startGpsAltitude = processedLocation.altitude.toFloat()
                                enhancedAltitude = startGpsAltitude!!
                                initAltitudeKalmanFilter(startGpsAltitude!!.toDouble())
                            }
                            
                            val currentAltitude = if (pressureSensor != null && startGpsAltitude != null) {
                                enhancedAltitude.toDouble()
                            } else {
                                applyAltitudeKalmanFilter(
                                    processedLocation.altitude,
                                    processedLocation.verticalAccuracyMeters.toDouble()
                                )
                            }
                            
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
        
        val currentAltitude = if (pressureSensor != null && startGpsAltitude != null) {
            enhancedAltitude.toDouble()
        } else {
            kalmanAltitude
        }
        
        // Pause 중이면 경과 시간 업데이트 안 함
        if (!isPaused) {
            updateElapsedTimeWithMillis(SystemClock.elapsedRealtime())
        }
        
        // ✅ 기압계 데이터 (필수)
        val barometerData = currentPressure?.let { pressure ->
            BarometerData(
                pressure = pressure,
                relativeAltitude = relativeAltitude,
                enhancedAltitude = enhancedAltitude
            )
        }
        
        // ✅ 모션 분석 결과 (Native에서 계산 완료)
        val motionAnalysis = if (useAccelerometer || useGyroscope) {
            generateMotionAnalysis()
        } else null

        val moving = isCurrentlyMoving
        
        // ✅ Grade 데이터
        val gradeData = resolveGradeData(location, currentAltitude, moving, updateStationaryState = true)
        
        // ✅ 세션 통계
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
        
        // ✅ 광센서 데이터
        val lightData = if (lastLuxTimestamp > 0) {
            LightData(
                lux = currentLux,
                condition = getLightCondition(currentLux),
                isLowLight = currentLux < 50
            )
        } else null
        
        // ✅ 소음 데이터
        val noiseData = if (lastDecibelTimestamp > 0 && currentDecibel > 0) {
            NoiseData(
                decibel = currentDecibel,
                noiseLevel = getNoiseLevel(currentDecibel)
            )
        } else null
        
        // ✅ 자기장 데이터
        val magnetometerData = if (useMagnetometer && magnetometerTimestamp > 0) {
            val strength = calculateMagneticFieldStrength(
                lastMagnetometerData[0],
                lastMagnetometerData[1],
                lastMagnetometerData[2]
            )
            Log.d(TAG, "📤 Sending magnetometer: heading=$magnetometerHeading, strength=$strength")
            MagnetometerData(
                heading = magnetometerHeading,
                magneticFieldStrength = strength,
                x = lastMagnetometerData[0],
                y = lastMagnetometerData[1],
                z = lastMagnetometerData[2]
            )
        } else {
            Log.d(TAG, "⚠️ Magnetometer NOT sent: useMagnetometer=$useMagnetometer, timestamp=$magnetometerTimestamp")
            null
        }
        
        val sensorData = SensorData(
            barometer = barometerData,
            motionAnalysis = motionAnalysis,
            grade = gradeData,
            sessionStats = sessionStats,
            light = lightData,
            noise = noiseData,
            magnetometer = magnetometerData
        )
        
        locationListener?.invoke(location, sensorData)
        updateNotification()
    }

    fun pause() {
        if (!isForegroundStarted) {
            Log.w(TAG, "⚠️ Cannot pause: tracking not started")
            return
        }
        
        if (isPaused) {
            Log.w(TAG, "⚠️ Already paused")
            return
        }
        
        isPaused = true
        pauseStartTime = SystemClock.elapsedRealtime()
        
        // Pause 시점의 previousLocation 저장 (resume 시 기준점으로 사용)
        pausedPreviousLocation = previousLocation?.let { Location(it) }
        pausedPreviousAltitude = previousAltitude
        
        Log.d(TAG, "⏸️ Tracking paused")
        updateNotification()
    }
    
    fun resume() {
        if (!isForegroundStarted) {
            Log.w(TAG, "⚠️ Cannot resume: tracking not started")
            return
        }
        
        if (!isPaused) {
            Log.w(TAG, "⚠️ Not paused")
            return
        }
        
        val resumeTime = SystemClock.elapsedRealtime()
        
        // Resume 시점에 lastElapsedUpdateTime을 현재 시간으로 업데이트
        // 이렇게 하면 pause 기간이 자동으로 제외됨
        lastElapsedUpdateTime = resumeTime
        
        // Resume 후 첫 번째 GPS 업데이트에서 거리 계산을 건너뛰도록 플래그 설정
        // (pause 시점 위치와 resume 후 위치 사이의 거리는 포함하지 않음)
        skipNextDistanceUpdate = true
        
        isPaused = false
        pauseStartTime = 0
        pausedPreviousLocation = null
        pausedPreviousAltitude = 0.0
        
        Log.d(TAG, "▶️ Tracking resumed")
        updateNotification()
    }
    
    fun stopForegroundTracking() {
        Log.d(TAG, "🛑 Stopping GPS tracking")
        
        Log.d(TAG, "[Stats] Final - Distance: %.2fm, Elevation Gain: %.2fm, Loss: %.2fm, Max Speed: %.2fm/s, Moving Time: %.0fs, Elapsed Time: %.0fs"
            .format(sessionDistance, sessionElevationGain, sessionElevationLoss, sessionMaxSpeed, sessionMovingTime, sessionElapsedTime))
        
        stopRepeatLocationUpdates()
        cleanupSingleLocationRequest()

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
        
        // Pause 상태 초기화
        isPaused = false
        pauseStartTime = 0
        pausedPreviousLocation = null
        pausedPreviousAltitude = 0.0
        skipNextDistanceUpdate = false
        
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
    
    fun isMoving(): Boolean = isCurrentlyMoving
    
    fun getFilteredSpeed(): Double = currentFilteredSpeed
    
    fun getLastRawLatitude(): Double? = lastRawLatitude
    
    fun getLastRawLongitude(): Double? = lastRawLongitude
    
    fun getLastRawAltitude(): Double? = lastRawAltitude
    
    fun getLastSensorData(): SensorData? {
        val currentAltitude = if (pressureSensor != null && startGpsAltitude != null) {
            enhancedAltitude.toDouble()
        } else {
            kalmanAltitude
        }
        
        val barometerData = currentPressure?.let {
            BarometerData(currentPressure!!, relativeAltitude, enhancedAltitude)
        }
        
        val motionAnalysis = if (useAccelerometer || useGyroscope) generateMotionAnalysis() else null
        
        val moving = isCurrentlyMoving
        
        val gradeData = lastLocation?.let { location ->
            resolveGradeData(location, currentAltitude, moving, updateStationaryState = false)
        }
        
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
        
        val lightData = if (lastLuxTimestamp > 0) {
            LightData(
                lux = currentLux,
                condition = getLightCondition(currentLux),
                isLowLight = currentLux < 50
            )
        } else null
        
        val noiseData = if (lastDecibelTimestamp > 0 && currentDecibel > 0) {
            NoiseData(
                decibel = currentDecibel,
                noiseLevel = getNoiseLevel(currentDecibel)
            )
        } else null
        
        val magnetometerData = if (useMagnetometer && magnetometerTimestamp > 0) {
            val strength = calculateMagneticFieldStrength(
                lastMagnetometerData[0],
                lastMagnetometerData[1],
                lastMagnetometerData[2]
            )
            MagnetometerData(
                heading = magnetometerHeading,
                magneticFieldStrength = strength,
                x = lastMagnetometerData[0],
                y = lastMagnetometerData[1],
                z = lastMagnetometerData[2]
            )
        } else null
        
        return SensorData(
            barometerData, 
            motionAnalysis,
            gradeData,
            sessionStats,
            lightData,
            noiseData,
            magnetometerData
        )
    }
    
    fun isBarometerAvailable(): Boolean = pressureSensor != null
    fun isAccelerometerAvailable(): Boolean = accelerometerSensor != null
    fun isGyroscopeAvailable(): Boolean = gyroscopeSensor != null
    fun isMagnetometerAvailable(): Boolean = magnetometerSensor != null
    fun isLightAvailable(): Boolean = lightSensor != null
    fun isNoiseAvailable(): Boolean {
        // 소음 센서는 마이크 하드웨어와 권한이 필요
        try {
            val bufferSize = AudioRecord.getMinBufferSize(
                44100,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            if (bufferSize == AudioRecord.ERROR || bufferSize == AudioRecord.ERROR_BAD_VALUE) {
                return false
            }
            // 실제 초기화는 시도하지 않고 버퍼 크기만 확인
            return true
        } catch (e: Exception) {
            return false
        }
    }
    
    fun getAvailableSensors(): Map<String, Boolean> {
        return mapOf(
            "accelerometer" to isAccelerometerAvailable(),
            "gyroscope" to isGyroscopeAvailable(),
            "magnetometer" to isMagnetometerAvailable(),
            "light" to isLightAvailable(),
            "noise" to isNoiseAvailable()
        )
    }
    
    fun isTracking(): Boolean = isForegroundStarted
    fun isPaused(): Boolean = isPaused
    fun getExerciseType(): String = exerciseType
    fun getUseAccelerometer(): Boolean = useAccelerometer
    fun getUseGyroscope(): Boolean = useGyroscope
    fun getUseMagnetometer(): Boolean = useMagnetometer
    fun getUseLight(): Boolean = useLight
    fun getUseNoise(): Boolean = useNoise
    fun isUsingKalmanFilter(): Boolean = useKalmanFilter
    fun isKalmanFiltered(): Boolean = useKalmanFilter && isKalmanInitialized

    fun requestSingleLocation(timeoutMs: Long = 10_000L, onResult: (Location?) -> Unit) {
        lastLocation?.let {
            Log.d(TAG, "📍 Returning cached location for single request")
            onResult(it)
            return
        }

        val client = fusedLocationClient
        if (client == null) {
            Log.e(TAG, "❌ FusedLocationClient unavailable for single request")
            onResult(null)
            return
        }

        cleanupSingleLocationRequest()

        val request = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 0L).apply {
            setMinUpdateIntervalMillis(0)
            setMaxUpdateDelayMillis(timeoutMs)
            setGranularity(Granularity.GRANULARITY_FINE)
            setWaitForAccurateLocation(true)
            setMaxUpdates(1)
        }.build()

        val singleCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                Log.d(TAG, "✅ Single location received")
                cleanupSingleLocationRequest()

                val location = locationResult.lastLocation
                if (location != null) {
                    lastLocation = location
                    isNewLocationAvailable = true
                }
                onResult(location)
            }

            override fun onLocationAvailability(locationAvailability: LocationAvailability) {
                Log.d(TAG, "ℹ️ Single request availability: ${locationAvailability.isLocationAvailable}")
            }
        }

        val timeoutRunnable = Runnable {
            Log.w(TAG, "⚠️ Single location request timed out after ${timeoutMs}ms")
            cleanupSingleLocationRequest()
            onResult(null)
        }

        pendingSingleLocationCallback = singleCallback
        singleLocationTimeoutRunnable = timeoutRunnable

        try {
            singleLocationHandler.postDelayed(timeoutRunnable, timeoutMs)
            client.requestLocationUpdates(request, singleCallback, Looper.getMainLooper())
        } catch (e: SecurityException) {
            Log.e(TAG, "❌ SecurityException during single location request", e)
            cleanupSingleLocationRequest()
            onResult(null)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error requesting single location", e)
            cleanupSingleLocationRequest()
            onResult(null)
        }
    }

    private fun cleanupSingleLocationRequest() {
        pendingSingleLocationCallback?.let { callback ->
            fusedLocationClient?.removeLocationUpdates(callback)
        }
        pendingSingleLocationCallback = null

        singleLocationTimeoutRunnable?.let { runnable ->
            singleLocationHandler.removeCallbacks(runnable)
        }
        singleLocationTimeoutRunnable = null
    }

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