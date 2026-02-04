package com.example.chain_sos_flutter.module2.context

import com.example.chain_sos_flutter.module2.ack.AckData

class ConnectivityMonitor {

    fun estimateCrowdLevel(acks: List<AckData>): String {
        val uniqueNodes = acks.map { it.ackId }.distinct().size

        return when {
            uniqueNodes >= 6 -> "CROWDED"
            uniqueNodes >= 3 -> "MODERATE"
            else -> "SPARSE"
        }
    }

    fun calculateStabilityScore(acks: List<AckData>): Float {
        if (acks.isEmpty()) return 0f

        val avgRssi = acks.map { it.rssi }.average()

        return when {
            avgRssi > -60 -> 1.0f
            avgRssi > -75 -> 0.6f
            else -> 0.3f
        }
    }
}
