package com.rnridablegpstracker

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.*
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.facebook.react.module.annotations.ReactModule

@ReactModule(name = RNRidableGpsTrackerModule.NAME)
class RNRidableGpsTrackerModule(reactContext: ReactApplicationContext) :
    NativeRidableGpsTrackerSpec(reactContext) {

    private var locationService: LocationService? = null
    private var serviceBound = false
    private var lastLocationTimestamp: Long = 0
    private val mainHandler = Handler(Looper.getMainLooper())
    
    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            Log.d(TAG, "✅ Service connected")
            val binder = service as LocationService.LocalBinder
            locationService = binder.getService()
            serviceBound = true
            
            locationService?.setLocationListener { location, sensorData ->
                sendLocationEvent(location, sensorData)
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.d(TAG, "⚠️ Service disconnected")
            locationService = null
            serviceBound = false
        }
    }

    companion object {
        const val NAME = "RNRidableGpsTracker"
        private const val TAG = "RNRidableGpsTracker"
    }

    override fun getName(): String = NAME

    init {
        Log.d(TAG, "Module initialized")
        bindLocationService()
    }

    private fun bindLocationService() {
        try {
            val intent = Intent(reactApplicationContext, LocationService::class.java)
            reactApplicationContext.bindService(
                intent,
                serviceConnection,
                Context.BIND_AUTO_CREATE
            )
            Log.d(TAG, "🔗 Binding to LocationService")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to bind LocationService", e)
        }
    }

    override fun configure(config: ReadableMap, promise: Promise) {
        try {
            val distanceFilter = if (config.hasKey("distanceFilter")) {
                config.getDouble("distanceFilter").toFloat()
            } else 0f

            val interval = if (config.hasKey("interval")) {
                config.getInt("interval").toLong()
            } else 1000L

            val fastestInterval = if (config.hasKey("fastestInterval")) {
                config.getInt("fastestInterval").toLong()
            } else 1000L

            val desiredAccuracy = if (config.hasKey("desiredAccuracy")) {
                config.getString("desiredAccuracy") ?: "high"
            } else "high"

            val exerciseType = if (config.hasKey("exerciseType")) {
                config.getString("exerciseType") ?: "bicycle"
            } else "bicycle"
            
            val advancedTracking = if (config.hasKey("advancedTracking")) {
                config.getBoolean("advancedTracking")
            } else false

            locationService?.configure(
                distanceFilter,
                interval,
                fastestInterval,
                desiredAccuracy,
                exerciseType,
                advancedTracking
            )

            Log.d(TAG, "⚙️ Configuration: exerciseType=$exerciseType, advanced=$advancedTracking")
            promise.resolve(null)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to configure", e)
            promise.reject("CONFIGURE_ERROR", e.message, e)
        }
    }

    override fun start(promise: Promise) {
        try {
            if (!hasLocationPermission()) {
                promise.reject("PERMISSION_DENIED", "Location permission not granted")
                return
            }

            if (locationService?.isTracking() == true) {
                Log.d(TAG, "⚠️ Already tracking, stopping first...")
                locationService?.stopForegroundTracking()
                
                mainHandler.postDelayed({
                    startTrackingInternal(promise)
                }, 200)
            } else {
                if (locationService == null || !serviceBound) {
                    Log.d(TAG, "🔗 Service not bound, binding first...")
                    bindLocationService()
                    waitForServiceBinding(promise)
                } else {
                    startTrackingInternal(promise)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to start", e)
            promise.reject("START_ERROR", e.message, e)
        }
    }

    private fun waitForServiceBinding(promise: Promise, maxAttempts: Int = 20, attempt: Int = 0) {
        if (serviceBound && locationService != null) {
            Log.d(TAG, "✅ Service bound after $attempt attempts")
            startTrackingInternal(promise)
        } else if (attempt < maxAttempts) {
            mainHandler.postDelayed({
                waitForServiceBinding(promise, maxAttempts, attempt + 1)
            }, 100)
        } else {
            Log.e(TAG, "❌ Service binding timeout")
            promise.reject("SERVICE_BINDING_ERROR", "Failed to bind LocationService within timeout")
        }
    }

    private fun startTrackingInternal(promise: Promise) {
        try {
            if (locationService == null) {
                promise.reject("SERVICE_NOT_AVAILABLE", "LocationService is not bound")
                return
            }

            locationService?.setLocationListener { location, sensorData ->
                sendLocationEvent(location, sensorData)
            }

            val intent = Intent(reactApplicationContext, LocationService::class.java).apply {
                action = LocationService.ACTION_START
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                reactApplicationContext.startForegroundService(intent)
            } else {
                reactApplicationContext.startService(intent)
            }

            locationService?.startForegroundTracking()
            
            Log.d(TAG, "✅ Tracking started successfully")
            promise.resolve(null)
        } catch (e: SecurityException) {
            Log.e(TAG, "❌ Security exception", e)
            promise.reject("SECURITY_ERROR", e.message, e)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to start tracking", e)
            promise.reject("START_TRACKING_ERROR", e.message, e)
        }
    }

    override fun stop(promise: Promise) {
        try {
            Log.d(TAG, "🛑 Stopping tracking...")
            
            locationService?.removeLocationListener()
            locationService?.stopForegroundTracking()
            
            Log.d(TAG, "✅ Tracking stopped")
            promise.resolve(null)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to stop", e)
            promise.reject("STOP_ERROR", e.message, e)
        }
    }

    override fun getCurrentLocation(promise: Promise) {
        try {
            val location = locationService?.getLastLocation()
            val sensorData = locationService?.getLastSensorData()
            
            if (location != null) {
                promise.resolve(convertLocationToMap(location, sensorData, isNew = false))
            } else {
                promise.reject("NO_LOCATION", "No location available")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to get current location", e)
            promise.reject("GET_LOCATION_ERROR", e.message, e)
        }
    }

    override fun checkStatus(promise: Promise) {
        try {
            val status = Arguments.createMap().apply {
                putBoolean("isRunning", locationService?.isTracking() ?: false)
                putBoolean("isAuthorized", hasLocationPermission())
                putString("authorizationStatus", getAuthorizationStatus())
                putBoolean("isBarometerAvailable", locationService?.isBarometerAvailable() ?: false)
                putBoolean("isAccelerometerAvailable", locationService?.isAccelerometerAvailable() ?: false)
                putBoolean("isGyroscopeAvailable", locationService?.isGyroscopeAvailable() ?: false)
                putBoolean("isServiceBound", serviceBound)
                putString("exerciseType", locationService?.getExerciseType() ?: "unknown")
                putBoolean("advancedTracking", locationService?.getAdvancedTracking() ?: false)
                putBoolean("isKalmanEnabled", locationService?.isUsingKalmanFilter() ?: false)
            }
            promise.resolve(status)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to check status", e)
            promise.reject("CHECK_STATUS_ERROR", e.message, e)
        }
    }

    override fun requestPermissions(promise: Promise) {
        promise.resolve(hasLocationPermission())
    }

    override fun openLocationSettings() {
        try {
            val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            reactApplicationContext.startActivity(intent)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to open settings", e)
        }
    }

    override fun addListener(eventName: String) {
        Log.d(TAG, "👂 Listener added: $eventName")
    }

    override fun removeListeners(count: Double) {
        Log.d(TAG, "🔇 Removing $count listeners")
    }

    override fun enableListeners() {
        Log.d(TAG, "🔊 enableListeners called")
    }

    override fun disableListeners() {
        Log.d(TAG, "🔇 disableListeners called")
    }

    private fun hasLocationPermission(): Boolean {
        val fineLocation = ContextCompat.checkSelfPermission(
            reactApplicationContext,
            Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        val coarseLocation = ContextCompat.checkSelfPermission(
            reactApplicationContext,
            Manifest.permission.ACCESS_COARSE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED

        return fineLocation || coarseLocation
    }

    private fun getAuthorizationStatus(): String {
        return if (hasLocationPermission()) {
            "authorizedWhenInUse"
        } else {
            "denied"
        }
    }

    private fun convertLocationToMap(
        location: Location, 
        sensorData: LocationService.SensorData?,
        isNew: Boolean
    ): WritableMap {
        return Arguments.createMap().apply {
            // 기본 GPS 데이터
            putDouble("latitude", location.latitude)
            putDouble("longitude", location.longitude)
            putDouble("altitude", location.altitude)
            putDouble("accuracy", location.accuracy.toDouble())
            putDouble("speed", if (location.hasSpeed()) location.speed.toDouble() else 0.0)
            putDouble("bearing", if (location.hasBearing()) location.bearing.toDouble() else 0.0)
            putDouble("timestamp", location.time.toDouble())
            putBoolean("isNewLocation", isNew)
            putBoolean("isKalmanFiltered", locationService?.isKalmanFiltered() ?: false)
            
            sensorData?.let { data ->
                // 기압계 데이터
                data.barometer?.let { baro ->
                    putDouble("enhancedAltitude", baro.enhancedAltitude.toDouble())
                    putDouble("relativeAltitude", baro.relativeAltitude.toDouble())
                    putDouble("pressure", baro.pressure.toDouble())
                }
                
                // 가속계 데이터
                data.accelerometer?.let { accel ->
                    val accelMap = Arguments.createMap().apply {
                        putDouble("x", accel.x.toDouble())
                        putDouble("y", accel.y.toDouble())
                        putDouble("z", accel.z.toDouble())
                        putDouble("magnitude", accel.magnitude.toDouble())
                    }
                    putMap("accelerometer", accelMap)
                }
                
                // 자이로스코프 데이터
                data.gyroscope?.let { gyro ->
                    val gyroMap = Arguments.createMap().apply {
                        putDouble("x", gyro.x.toDouble())
                        putDouble("y", gyro.y.toDouble())
                        putDouble("z", gyro.z.toDouble())
                        putDouble("rotationRate", gyro.rotationRate.toDouble())
                    }
                    putMap("gyroscope", gyroMap)
                }
                
                // 운동 분석 데이터
                data.motionAnalysis?.let { motion ->
                    val motionMap = Arguments.createMap().apply {
                        putString("roadSurfaceQuality", motion.roadSurfaceQuality)
                        putDouble("vibrationIntensity", motion.vibrationIntensity.toDouble())
                        putDouble("corneringIntensity", motion.corneringIntensity.toDouble())
                        putDouble("inclineAngle", motion.inclineAngle.toDouble())
                        putBoolean("isClimbing", motion.isClimbing)
                        putBoolean("isDescending", motion.isDescending)
                        putDouble("verticalAcceleration", motion.verticalAcceleration.toDouble())
                    }
                    putMap("motionAnalysis", motionMap)
                }
                
                // 🆕 Grade 데이터
                data.grade?.let { grade ->
                    putDouble("grade", grade.grade.toDouble())
                    putString("gradeCategory", grade.gradeCategory)
                }
                
                // 🆕 세션 통계
                data.sessionStats?.let { stats ->
                    putDouble("sessionDistance", stats.distance)
                    putDouble("sessionElevationGain", stats.elevationGain)
                    putDouble("sessionElevationLoss", stats.elevationLoss)
                    putDouble("sessionMovingTime", stats.movingTime)
                    putDouble("sessionElapsedTime", stats.elapsedTime)
                    putDouble("sessionMaxSpeed", stats.maxSpeed.toDouble())
                    putDouble("sessionAvgSpeed", stats.avgSpeed)
                    putDouble("sessionMovingAvgSpeed", stats.movingAvgSpeed)
                }
            }
            
            // 🆕 이동 상태
            putBoolean("isMoving", if (location.hasSpeed()) location.speed >= 0.5f else false)
        }
    }

    private fun sendLocationEvent(location: Location, sensorData: LocationService.SensorData?) {
        try {
            val isNew = location.time != lastLocationTimestamp
            if (isNew) {
                lastLocationTimestamp = location.time
            }
            
            reactApplicationContext
                .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                .emit("location", convertLocationToMap(location, sensorData, isNew))
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to send location event", e)
        }
    }

    override fun onCatalystInstanceDestroy() {
        super.onCatalystInstanceDestroy()
        try {
            Log.d(TAG, "💀 Catalyst instance destroy")
            
            locationService?.removeLocationListener()
            
            if (serviceBound) {
                reactApplicationContext.unbindService(serviceConnection)
                serviceBound = false
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error during cleanup", e)
        }
    }
}