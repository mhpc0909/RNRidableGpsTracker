package com.rnridablegpstracker

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.net.Uri
import android.os.Build
import android.os.Looper
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat
import com.facebook.react.bridge.*
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.google.android.gms.location.*

class RNRidableGpsTrackerModule(private val reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext) {

    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationCallback: LocationCallback? = null
    private var isTracking = false
    private val config = mutableMapOf<String, Any>()
    private var currentLocationPromise: Promise? = null
    private var useForegroundService = true

    companion object {
        const val NAME = "RNRidableGpsTracker"
        private const val TAG = "RNRidableGpsTracker"
        private const val LOCATION_PERMISSION = Manifest.permission.ACCESS_FINE_LOCATION
        private const val BACKGROUND_LOCATION_PERMISSION = Manifest.permission.ACCESS_BACKGROUND_LOCATION
    }

    init {
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(reactContext)
        
        // Default configuration - Optimized for cycling with 1-second updates
        config["distanceFilter"] = 0.0 // 0 means no distance filter, rely on interval
        config["desiredAccuracy"] = "high"
        config["interval"] = 1000L // Exactly 1 second
        config["fastestInterval"] = 1000L // Also 1 second to ensure consistent updates
        config["useForegroundService"] = true
        
        // Set up location listener for service
        LocationService.locationListener = { location ->
            sendLocationEvent(location)
        }
        
        Log.d(TAG, "Module initialized")
    }

    override fun getName(): String = NAME

    @ReactMethod
    fun configure(config: ReadableMap, promise: Promise) {
        try {
            if (config.hasKey("distanceFilter")) {
                this.config["distanceFilter"] = config.getDouble("distanceFilter")
            }
            if (config.hasKey("desiredAccuracy")) {
                this.config["desiredAccuracy"] = config.getString("desiredAccuracy")
            }
            if (config.hasKey("interval")) {
                this.config["interval"] = config.getInt("interval").toLong()
            }
            if (config.hasKey("fastestInterval")) {
                this.config["fastestInterval"] = config.getInt("fastestInterval").toLong()
            }
            if (config.hasKey("useForegroundService")) {
                this.config["useForegroundService"] = config.getBoolean("useForegroundService")
                useForegroundService = config.getBoolean("useForegroundService")
            }
            
            Log.d(TAG, "Configuration updated: $config")
            promise.resolve(null)
        } catch (e: Exception) {
            Log.e(TAG, "Configuration error", e)
            promise.reject("CONFIG_ERROR", e.message, e)
        }
    }

    @SuppressLint("MissingPermission")
    @ReactMethod
    fun start(promise: Promise) {
        Log.d(TAG, "Start tracking called")
        
        if (isTracking || LocationService.isServiceRunning) {
            Log.d(TAG, "Already tracking. isTracking=$isTracking, serviceRunning=${LocationService.isServiceRunning}")
            promise.resolve(null)
            return
        }

        if (!hasLocationPermission()) {
            Log.e(TAG, "Location permission not granted")
            promise.reject("PERMISSION_DENIED", "Location permission not granted")
            return
        }

        try {
            Log.d(TAG, "Starting foreground service: useForegroundService=$useForegroundService")
            
            if (useForegroundService) {
                startForegroundService()
            } else {
                startLocationUpdatesDirectly()
            }
            
            isTracking = true
            Log.d(TAG, "Tracking started successfully")
            promise.resolve(null)
        } catch (e: Exception) {
            Log.e(TAG, "Error starting tracking", e)
            promise.reject("START_ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun stop(promise: Promise) {
        Log.d(TAG, "Stop tracking called")
        
        if (!isTracking && !LocationService.isServiceRunning) {
            Log.d(TAG, "Already stopped")
            promise.resolve(null)
            return
        }

        try {
            if (useForegroundService && LocationService.isServiceRunning) {
                stopForegroundService()
            } else {
                stopLocationUpdatesDirectly()
            }
            
            isTracking = false
            Log.d(TAG, "Tracking stopped successfully")
            promise.resolve(null)
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping tracking", e)
            promise.reject("STOP_ERROR", e.message, e)
        }
    }

    @SuppressLint("MissingPermission")
    @ReactMethod
    fun getCurrentLocation(promise: Promise) {
        if (!hasLocationPermission()) {
            promise.reject("PERMISSION_DENIED", "Location permission not granted")
            return
        }

        currentLocationPromise = promise

        try {
            fusedLocationClient?.lastLocation?.addOnSuccessListener { location ->
                if (location != null) {
                    val locationMap = locationToMap(location)
                    currentLocationPromise?.resolve(locationMap)
                    currentLocationPromise = null
                } else {
                    // Request a single location update
                    val locationRequest = createLocationRequest()
                    val callback = object : LocationCallback() {
                        override fun onLocationResult(locationResult: LocationResult) {
                            locationResult.lastLocation?.let {
                                val locationMap = locationToMap(it)
                                currentLocationPromise?.resolve(locationMap)
                                currentLocationPromise = null
                            }
                            fusedLocationClient?.removeLocationUpdates(this)
                        }
                    }
                    fusedLocationClient?.requestLocationUpdates(
                        locationRequest,
                        callback,
                        Looper.getMainLooper()
                    )
                }
            }?.addOnFailureListener { e ->
                currentLocationPromise?.reject("LOCATION_ERROR", e.message, e)
                currentLocationPromise = null
            }
        } catch (e: Exception) {
            promise.reject("LOCATION_ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun checkStatus(promise: Promise) {
        try {
            val isAuthorized = hasLocationPermission()
            val authStatus = when {
                hasLocationPermission() && hasBackgroundLocationPermission() -> "authorizedAlways"
                hasLocationPermission() -> "authorizedWhenInUse"
                else -> "denied"
            }

            val status = Arguments.createMap().apply {
                putBoolean("isRunning", isTracking || LocationService.isServiceRunning)
                putBoolean("isAuthorized", isAuthorized)
                putString("authorizationStatus", authStatus)
                putBoolean("isServiceRunning", LocationService.isServiceRunning)
            }

            Log.d(TAG, "Status: isRunning=${isTracking || LocationService.isServiceRunning}, " +
                    "isAuthorized=$isAuthorized, serviceRunning=${LocationService.isServiceRunning}")
            promise.resolve(status)
        } catch (e: Exception) {
            promise.reject("STATUS_ERROR", e.message, e)
        }
    }

    @ReactMethod
    fun requestPermissions(promise: Promise) {
        // Note: Actual permission request should be handled by the app
        // This just checks current permission status
        val granted = hasLocationPermission()
        promise.resolve(granted)
    }

    @ReactMethod
    fun openLocationSettings() {
        try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.fromParts("package", reactContext.packageName, null)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            reactContext.startActivity(intent)
        } catch (e: Exception) {
            // Fallback to general location settings
            val intent = Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            reactContext.startActivity(intent)
        }
    }

    @ReactMethod
    fun addListener(eventName: String) {
        // Required for EventEmitter
    }

    @ReactMethod
    fun removeListeners(count: Int) {
        // Required for EventEmitter
    }

    // Foreground Service methods
    private fun startForegroundService() {
        val interval = (config["interval"] as? Long) ?: 1000L
        val fastestInterval = (config["fastestInterval"] as? Long) ?: 1000L
        val distanceFilter = (config["distanceFilter"] as? Double)?.toFloat() ?: 0f
        val accuracy = config["desiredAccuracy"] as? String ?: "high"
        
        val priority = when (accuracy) {
            "high" -> LocationRequest.PRIORITY_HIGH_ACCURACY
            "medium" -> LocationRequest.PRIORITY_BALANCED_POWER_ACCURACY
            else -> LocationRequest.PRIORITY_LOW_POWER
        }

        Log.d(TAG, "Starting foreground service with interval=$interval, fastestInterval=$fastestInterval")

        val serviceIntent = Intent(reactContext, LocationService::class.java).apply {
            action = LocationService.ACTION_START
            putExtra(LocationService.EXTRA_INTERVAL, interval)
            putExtra(LocationService.EXTRA_FASTEST_INTERVAL, fastestInterval)
            putExtra(LocationService.EXTRA_DISTANCE_FILTER, distanceFilter)
            putExtra(LocationService.EXTRA_PRIORITY, priority)
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                reactContext.startForegroundService(serviceIntent)
                Log.d(TAG, "startForegroundService called (Android O+)")
            } else {
                reactContext.startService(serviceIntent)
                Log.d(TAG, "startService called (pre-Android O)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error starting foreground service", e)
            throw e
        }
    }

    private fun stopForegroundService() {
        val serviceIntent = Intent(reactContext, LocationService::class.java).apply {
            action = LocationService.ACTION_STOP
        }
        reactContext.startService(serviceIntent)
        Log.d(TAG, "Stop service intent sent")
    }

    // Direct location updates methods (fallback)
    @SuppressLint("MissingPermission")
    private fun startLocationUpdatesDirectly() {
        val locationRequest = createLocationRequest()
        
        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                locationResult.lastLocation?.let { location ->
                    sendLocationEvent(location)
                }
            }
        }

        fusedLocationClient?.requestLocationUpdates(
            locationRequest,
            locationCallback!!,
            Looper.getMainLooper()
        )
        Log.d(TAG, "Direct location updates started")
    }

    private fun stopLocationUpdatesDirectly() {
        locationCallback?.let {
            fusedLocationClient?.removeLocationUpdates(it)
        }
        locationCallback = null
        Log.d(TAG, "Direct location updates stopped")
    }

    private fun createLocationRequest(): LocationRequest {
        val interval = (config["interval"] as? Long) ?: 1000L
        val fastestInterval = (config["fastestInterval"] as? Long) ?: 1000L
        val accuracy = config["desiredAccuracy"] as? String ?: "high"
        
        val priority = when (accuracy) {
            "high" -> LocationRequest.PRIORITY_HIGH_ACCURACY
            "medium" -> LocationRequest.PRIORITY_BALANCED_POWER_ACCURACY
            else -> LocationRequest.PRIORITY_LOW_POWER
        }

        return LocationRequest.create().apply {
            // Set both interval and fastestInterval to 1 second to ensure consistent 1-second updates
            this.interval = interval
            this.fastestInterval = fastestInterval
            this.priority = priority
            
            // Set distance filter to 0 to get updates based on time, not distance
            val distanceFilter = (config["distanceFilter"] as? Double)?.toFloat() ?: 0f
            this.smallestDisplacement = distanceFilter
        }
    }

    private fun hasLocationPermission(): Boolean {
        return ContextCompat.checkSelfPermission(
            reactContext,
            LOCATION_PERMISSION
        ) == PackageManager.PERMISSION_GRANTED
    }

    private fun hasBackgroundLocationPermission(): Boolean {
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
            ContextCompat.checkSelfPermission(
                reactContext,
                BACKGROUND_LOCATION_PERMISSION
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    private fun locationToMap(location: Location): WritableMap {
        return Arguments.createMap().apply {
            putDouble("latitude", location.latitude)
            putDouble("longitude", location.longitude)
            putDouble("altitude", location.altitude)
            putDouble("accuracy", location.accuracy.toDouble())
            putDouble("speed", if (location.hasSpeed()) location.speed.toDouble() else 0.0)
            putDouble("bearing", if (location.hasBearing()) location.bearing.toDouble() else 0.0)
            putDouble("timestamp", location.time.toDouble())
        }
    }

    private fun sendLocationEvent(location: Location) {
        val locationMap = locationToMap(location)
        sendEvent("location", locationMap)
    }

    private fun sendEvent(eventName: String, params: WritableMap?) {
        reactContext
            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit(eventName, params)
    }
}
