package com.example.chain_sos_flutter.module2.ack

object AckCollector {

    private val ackBuffer = mutableListOf<AckData>()

    fun addAck(ack: AckData) {
        ackBuffer.add(ack)
    }

    fun consumeAcks(): List<AckData> {
        val copy = ackBuffer.toList()
        ackBuffer.clear()
        return copy
    }
}
