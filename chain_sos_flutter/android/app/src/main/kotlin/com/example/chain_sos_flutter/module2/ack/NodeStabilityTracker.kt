package com.example.chain_sos_flutter.module2.ack

/**
 * Tracks per-device ACK behavior across time windows
 * and identifies stable nodes.
 */
class NodeStabilityTracker(
    private val stableWindowThreshold: Int = 3,
    private val maxAllowedDelayMs: Long = 1500
) {

    private data class NodeState(
        var consecutiveWindows: Int = 0,
        var lastAvgDelayMs: Long = 0,
        var missedWindows: Int = 0
    )

    private val nodeStates = mutableMapOf<String, NodeState>()

    /**
     * Call this once per time window.
     *
     * @param senderDelays map of senderId -> avg delay in this window
     */
    fun updateWindow(senderDelays: Map<String, Long>) {

        // Mark all existing nodes as missed initially
        nodeStates.values.forEach { it.missedWindows++ }

        for ((senderId, avgDelay) in senderDelays) {
            val state = nodeStates.getOrPut(senderId) { NodeState() }

            state.consecutiveWindows++
            state.missedWindows = 0
            state.lastAvgDelayMs = avgDelay
        }

        // Remove nodes that disappeared for too long
        nodeStates.entries.removeIf { it.value.missedWindows >= 2 }
    }

    /**
     * Returns list of stable node IDs.
     */
    fun getStableNodes(): List<String> {
        return nodeStates.filter { (_, state) ->
            state.consecutiveWindows >= stableWindowThreshold &&
            state.lastAvgDelayMs <= maxAllowedDelayMs
        }.keys.toList()
    }
}
