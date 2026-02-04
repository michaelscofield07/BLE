package com.example.chain_sos_flutter.module2.intelligence

/**
 * Immutable snapshot of device + network context
 * used for AI / decision-making.
 */
data class FeatureVector(
    val batteryLevel: Int,
    val isCharging: Boolean,
    val temperature: Float,
    val stabilityScore: Float,
    val crowdLevel: String,
    val stableNodeCount: Int,
    val timestamp: Long
) {
    companion object {
        fun fromStore(): FeatureVector {
            return FeatureVector(
                batteryLevel = DeviceContextStore.batteryLevel,
                isCharging = DeviceContextStore.isCharging,
                temperature = DeviceContextStore.temperature,
                stabilityScore = DeviceContextStore.stabilityScore,
                crowdLevel = DeviceContextStore.crowdLevel,
                stableNodeCount = DeviceContextStore.stableNodeCount,
                timestamp = DeviceContextStore.lastUpdated
            )
        }
    }
}
