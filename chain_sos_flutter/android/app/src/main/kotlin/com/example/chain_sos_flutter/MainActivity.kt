package com.example.chain_sos_flutter  // keep your package name same as in AndroidManifest.xml

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "ble_advertiser"
    private var advertiserCallback: AdvertiseCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
