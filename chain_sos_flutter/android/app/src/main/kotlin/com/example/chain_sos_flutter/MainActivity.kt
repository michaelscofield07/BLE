package com.example.chain_sos_flutter  // keep your package name same as in AndroidManifest.xml

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.example.chain_sos_flutter.module2.ack.AckCollector
import com.example.chain_sos_flutter.module2.ack.NodeStabilityTracker
import com.example.chain_sos_flutter.module2.context.BatteryMonitor
import com.example.chain_sos_flutter.module2.context.ConnectivityMonitor
import com.example.chain_sos_flutter.module2.context.TemperatureMonitor
import com.example.chain_sos_flutter.module2.intelligence.DeviceContextStore
import com.example.chain_sos_flutter.module2.intelligence.FeatureVector
import kotlinx.coroutines.*

class MainActivity : FlutterActivity() {

    private val BLE_CHANNEL = "ble_advertiser"
    private val INTELLIGENT_SOS_CHANNEL = "intelligent_sos"
    private var advertiserCallback: AdvertiseCallback? = null
    
    // Module-2 components
    private lateinit var batteryMonitor: BatteryMonitor
    private lateinit var connectivityMonitor: ConnectivityMonitor
    private lateinit var temperatureMonitor: TemperatureMonitor
    private lateinit var nodeStabilityTracker: NodeStabilityTracker
    private lateinit var handler: Handler
    private var monitoringJob: Job? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Initialize Module-2 components
        initializeModule2Components()

        // Setup BLE method channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BLE_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAdvertising" -> {
                    val payload = call.argument<List<Int>>("payload") ?: emptyList()
                    val bytes = ByteArray(payload.size) { i -> payload[i].toByte() }
                    startAdvertising(bytes)
                    result.success(null)
                }
                "stopAdvertising" -> {
                    stopAdvertising()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Setup Intelligent SOS method channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, INTELLIGENT_SOS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    initializeIntelligentSos()
                    result.success(null)
                }
                "getDeviceContext" -> {
                    result.success(getDeviceContext())
                }
                "addAckData" -> {
                    addAckData(
                        call.argument("ackId") ?: "",
                        call.argument("sosId") ?: "",
                        call.argument("rssi") ?: 0,
                        call.argument("timestamp") ?: 0L
                    )
                    result.success(null)
                }
                "getStableNodes" -> {
                    result.success(getStableNodes())
                }
                "getNetworkStabilityScore" -> {
                    result.success(getNetworkStabilityScore())
                }
                "getCrowdLevel" -> {
                    result.success(getCrowdLevel())
                }
                "getFeatureVector" -> {
                    result.success(getFeatureVector())
                }
                "startMonitoring" -> {
                    startMonitoring()
                    result.success(null)
                }
                "stopMonitoring" -> {
                    stopMonitoring()
                    result.success(null)
                }
                "getSosDecision" -> {
                    result.success(getSosDecision())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun initializeModule2Components() {
        batteryMonitor = BatteryMonitor(this)
        connectivityMonitor = ConnectivityMonitor()
        temperatureMonitor = TemperatureMonitor(this)
        nodeStabilityTracker = NodeStabilityTracker()
        handler = Handler(Looper.getMainLooper())
        
        Log.d("IntelligentSOS", "Module-2 components initialized")
    }

    private fun initializeIntelligentSos() {
        // Update initial device context
        updateDeviceContext()
        Log.d("IntelligentSOS", "Intelligent SOS service initialized")
    }

    private fun updateDeviceContext() {
        try {
            DeviceContextStore.apply {
                batteryLevel = batteryMonitor.getBatteryLevel()
                isCharging = batteryMonitor.isCharging()
                temperature = temperatureMonitor.getBatteryTemperature()
                lastUpdated = System.currentTimeMillis()
            }
            
            // Update network intelligence
            val acks = AckCollector.consumeAcks()
            if (acks.isNotEmpty()) {
                val crowdLevel = connectivityMonitor.estimateCrowdLevel(acks)
                val stabilityScore = connectivityMonitor.calculateStabilityScore(acks)
                
                DeviceContextStore.apply {
                    this.crowdLevel = crowdLevel
                    this.stabilityScore = stabilityScore
                }
                
                // Update node stability tracker
                val senderDelays = acks.groupBy { it.ackId }
                    .mapValues { (_, ackList) -> ackList.map { it.timestamp }.average().toLong() }
                nodeStabilityTracker.updateWindow(senderDelays)
                
                DeviceContextStore.stableNodeCount = nodeStabilityTracker.getStableNodes().size
            }
            
        } catch (e: Exception) {
            Log.e("IntelligentSOS", "Error updating device context: ${e.message}")
        }
    }

    private fun getDeviceContext(): Map<String, Any> {
        return mapOf(
            "batteryLevel" to DeviceContextStore.batteryLevel,
            "isCharging" to DeviceContextStore.isCharging,
            "temperature" to DeviceContextStore.temperature,
            "stabilityScore" to DeviceContextStore.stabilityScore,
            "crowdLevel" to DeviceContextStore.crowdLevel,
            "stableNodeCount" to DeviceContextStore.stableNodeCount,
            "lastUpdated" to DeviceContextStore.lastUpdated
        )
    }

    private fun addAckData(ackId: String, sosId: String, rssi: Int, timestamp: Long) {
        val ackData = com.example.chain_sos_flutter.module2.ack.AckData(
            ackId = ackId,
            sosId = sosId,
            rssi = rssi,
            timestamp = timestamp
        )
        AckCollector.addAck(ackData)
        
        // Update context immediately when new ACK arrives
        updateDeviceContext()
        
        Log.d("IntelligentSOS", "ACK received: $ackId, RSSI: $rssi")
    }

    private fun getStableNodes(): List<String> {
        return nodeStabilityTracker.getStableNodes()
    }

    private fun getNetworkStabilityScore(): Double {
        return DeviceContextStore.stabilityScore.toDouble()
    }

    private fun getCrowdLevel(): String {
        return DeviceContextStore.crowdLevel
    }

    private fun getFeatureVector(): Map<String, Any> {
        val vector = FeatureVector.fromStore()
        return mapOf(
            "batteryLevel" to vector.batteryLevel,
            "isCharging" to vector.isCharging,
            "temperature" to vector.temperature,
            "stabilityScore" to vector.stabilityScore,
            "crowdLevel" to vector.crowdLevel,
            "stableNodeCount" to vector.stableNodeCount,
            "timestamp" to vector.timestamp
        )
    }

    private fun startMonitoring() {
        monitoringJob?.cancel()
        monitoringJob = CoroutineScope(Dispatchers.IO).launch {
            while (isActive) {
                updateDeviceContext()
                delay(5000) // Update every 5 seconds
            }
        }
        Log.d("IntelligentSOS", "Started continuous monitoring")
    }

    private fun stopMonitoring() {
        monitoringJob?.cancel()
        Log.d("IntelligentSOS", "Stopped continuous monitoring")
    }

    private fun getSosDecision(): Map<String, Any> {
        val context = getDeviceContext()
        val batteryLevel = context["batteryLevel"] as Int
        val stabilityScore = context["stabilityScore"] as Double
        val crowdLevel = context["crowdLevel"] as String
        val stableNodes = getStableNodes()
        
        val shouldForward = when {
            batteryLevel < 20 -> false // Low battery, conserve energy
            stabilityScore < 0.3 && crowdLevel == "SPARSE" -> false // Poor network, sparse crowd
            else -> true
        }
        
        val priority = when {
            batteryLevel < 10 -> "low"
            stabilityScore > 0.8 && crowdLevel == "CROWDED" -> "high"
            else -> "normal"
        }
        
        val selectedNodes = if (shouldForward) stableNodes.take(3) else emptyList()
        
        val reason = when {
            batteryLevel < 20 -> "Low battery mode"
            stabilityScore < 0.3 -> "Poor network stability"
            crowdLevel == "SPARSE" -> "Sparse crowd, limited forwarding"
            else -> "Normal operation"
        }
        
        return mapOf(
            "shouldForward" to shouldForward,
            "priority" to priority,
            "selectedNodes" to selectedNodes,
            "reason" to reason
        )
    }

    private fun hasBlePermissions(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val adv = checkSelfPermission(android.Manifest.permission.BLUETOOTH_ADVERTISE) == PackageManager.PERMISSION_GRANTED
            val scan = checkSelfPermission(android.Manifest.permission.BLUETOOTH_SCAN) == PackageManager.PERMISSION_GRANTED
            val conn = checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED
            if (!adv || !scan || !conn) {
                Log.w("BLE_ADVERT", "Missing Android 12+ BLE permissions: advertise=$adv scan=$scan connect=$conn")
                return false
            }
        }
        return true
    }

    private fun startAdvertising(payload: ByteArray) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            Log.e("BLE_ADVERT", "BLE advertising requires API 21+")
            return
        }

        if (!hasBlePermissions()) {
            Log.w("BLE_ADVERT", "Cannot advertise: missing runtime permissions")
            return
        }

        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter
        if (adapter == null) {
            Log.e("BLE_ADVERT", "Bluetooth adapter not available")
            return
        }
        if (!adapter.isEnabled) {
            Log.w("BLE_ADVERT", "Bluetooth is disabled")
            return
        }
        val advertiser = adapter.bluetoothLeAdvertiser
        if (advertiser == null) {
            Log.e("BLE_ADVERT", "BluetoothLeAdvertiser not available on this device")
            return
        }

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(false)
            .build()

        val data = AdvertiseData.Builder()
            .addManufacturerData(0x1337, payload)
            .setIncludeDeviceName(false)
            .build()

        advertiserCallback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                Log.i("BLE_ADVERT", "Advertising started successfully")
            }

            override fun onStartFailure(errorCode: Int) {
                Log.e("BLE_ADVERT", "Advertising failed: $errorCode")
            }
        }

        advertiser.startAdvertising(settings, data, advertiserCallback)
    }

    private fun stopAdvertising() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) return
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter ?: return
        val advertiser = adapter.bluetoothLeAdvertiser ?: return
        advertiserCallback?.let { cb ->
            advertiser.stopAdvertising(cb)
        }
        advertiserCallback = null
        Log.i("BLE_ADVERT", "Advertising stopped")
    }
}
