package com.example.chain_sos_flutter.module2.intelligence

/**
 * Shared in-memory store for the latest SOS-related context.
 *
 * - Written by: SOSService / collectors
 * - Read by: FeatureVector / AI / other modules
 *
 * This is NOT persistent storage.
 * Data lives only while the app/process is alive.
 */
object DeviceContextStore {

    @Volatile
    var batteryLevel: Int = -1          // 0–100, -1 = unknown

    @Volatile
    var isCharging: Boolean = false

    @Volatile
    var temperature: Float = -1f        // Celsius, -1 = unknown

    @Volatile
    var stabilityScore: Float = 0f      // 0.0 – 1.0

    @Volatile
    var crowdLevel: String = "UNKNOWN"  // SPARSE / MODERATE / CROWDED

    @Volatile
    var stableNodeCount: Int = 0

    @Volatile
    var lastUpdated: Long = 0L          // System.currentTimeMillis()
}
