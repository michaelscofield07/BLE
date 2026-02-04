package com.example.chain_sos_flutter.module2.ack


data class AckData(
    val ackId: String,
    val sosId: String,
    val rssi: Int,
    val timestamp: Long
)

