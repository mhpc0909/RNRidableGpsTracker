package com.rnridablegpstracker

import android.Manifest
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.os.IBinder
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
    
    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            Log.d(TAG, "Service connected")
            val binder = service as LocationService.LocalBinder
            locationService = binder.getService()
            serviceBound = true
            
            locationService?.setLocationListener { location, barometerData ->
                sendLocationEvent(location, barometerData)
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.d(TAG, "Service disconnected")
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
            Log.d(TAG, "Binding to LocationService")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to bind LocationService", e)
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

            // 🆕 exerciseType 처리
            val exerciseType = if (config.hasKey("exerciseType")) {
                config.getString("exerciseType") ?: "bicycle"
            } else {
                "bicycle"  // 기본값
            }
            
            when (exerciseType) {
                "bicycle" -> {
                    // 자전거 설정
                    // 필요한 설정 적용
                }
                "running" -> {
                    // 러닝 설정
                }
                "hiking" -> {
                    // 하이킹 설정
                }
                "walking" -> {
                    // 걷기 설정
                }
            }

            locationService?.configure(
                distanceFilter,
                interval,
                fastestInterval,
                desiredAccuracy,
                exerciseType  // 🆕 exerciseType 전달
            )

            Log.d(TAG, "Configuration applied with exerciseType: $exerciseType")
            promise.resolve(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to configure", e)
            promise.reject("CONFIGURE_ERROR", e.message, e)
        }
    }

    override fun start(promise: Promise) {
        try {
            if (!hasLocationPermission()) {
                promise.reject("PERMISSION_DENIED", "Location permission not granted")
                return
            }

            if (locationService == null) {
                bindLocationService()
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    startTracking(promise)
                }, 500)
            } else {
                startTracking(promise)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start", e)
            promise.reject("START_ERROR", e.message, e)
        }
    }

    private fun startTracking(promise: Promise) {
        try {
            val intent = Intent(reactApplicationContext, LocationService::class.java).apply {
                action = LocationService.ACTION_START
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                reactApplicationContext.startForegroundService(intent)
            } else {
                reactApplicationContext.startService(intent)
            }

            locationService?.startForegroundTracking()
            Log.d(TAG, "Tracking started")
            promise.resolve(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start tracking", e)
            promise.reject("START_TRACKING_ERROR", e.message, e)
        }
    }

    override fun stop(promise: Promise) {
        try {
            locationService?.stopForegroundTracking()
            
            val intent = Intent(reactApplicationContext, LocationService::class.java)
            reactApplicationContext.stopService(intent)
            
            Log.d(TAG, "Tracking stopped")
            promise.resolve(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop", e)
            promise.reject("STOP_ERROR", e.message, e)
        }
    }

    override fun getCurrentLocation(promise: Promise) {
        try {
            val location = locationService?.getLastLocation()
            val barometerData = locationService?.getLastBarometerData()
            
            if (location != null) {
                promise.resolve(convertLocationToMap(location, barometerData, isNew = false))
            } else {
                promise.reject("NO_LOCATION", "No location available")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get current location", e)
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
            }
            promise.resolve(status)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to check status", e)
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
            Log.e(TAG, "Failed to open settings", e)
        }
    }

    override fun addListener(eventName: String) {
        Log.d(TAG, "Listener added: $eventName")
    }

    override fun removeListeners(count: Double) {
        Log.d(TAG, "Removing $count listeners")
    }

    override fun enableListeners() {
        Log.d(TAG, "enableListeners called")
    }

    override fun disableListeners() {
        Log.d(TAG, "disableListeners called")
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
        barometerData: LocationService.BarometerData?,
        isNew: Boolean
    ): WritableMap {
        return Arguments.createMap().apply {
            putDouble("latitude", location.latitude)
            putDouble("longitude", location.longitude)
            putDouble("altitude", location.altitude)  // GPS 기반 고도
            putDouble("accuracy", location.accuracy.toDouble())
            putDouble("speed", if (location.hasSpeed()) location.speed.toDouble() else 0.0)
            putDouble("bearing", if (location.hasBearing()) location.bearing.toDouble() else 0.0)
            putDouble("timestamp", location.time.toDouble())
            putBoolean("isNewLocation", isNew)  // 🆕 새 위치 데이터 여부
            
            // 기압계 데이터 추가
            barometerData?.let { data ->
                putDouble("enhancedAltitude", data.enhancedAltitude.toDouble())  // 보정된 고도
                putDouble("relativeAltitude", data.relativeAltitude.toDouble())  // 상대 고도
                putDouble("pressure", data.pressure.toDouble())  // 기압 (hPa)
            }
        }
    }

    private fun sendLocationEvent(location: Location, barometerData: LocationService.BarometerData?) {
        try {
            // 새로운 위치인지 확인 (timestamp 비교)
            val isNew = location.time != lastLocationTimestamp
            if (isNew) {
                lastLocationTimestamp = location.time
            }
            
            reactApplicationContext
                .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
                .emit("location", convertLocationToMap(location, barometerData, isNew))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to send location event", e)
        }
    }

    override fun onCatalystInstanceDestroy() {
        super.onCatalystInstanceDestroy()
        try {
            if (serviceBound) {
                reactApplicationContext.unbindService(serviceConnection)
                serviceBound = false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error unbinding service", e)
        }
    }
}