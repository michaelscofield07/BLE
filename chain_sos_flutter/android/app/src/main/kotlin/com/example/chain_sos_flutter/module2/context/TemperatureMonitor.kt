package com.example.chain_sos_flutter.module2.context

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager

class TemperatureMonitor(private val context: Context) {

    /**
     * Returns battery temperature in Celsius.
     * Android reports temperature in tenths of a degree.
     * Returns -1f if unavailable.
     */
    fun getBatteryTemperature(): Float {
        val intent: Intent? = context.registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        )

        val temp = intent?.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, -1) ?: -1

        return if (temp > 0) {
            temp / 10f
        } else {
            -1f
        }
    }

    /**
     * Returns true if battery temperature is considered overheating.
     */
    fun isOverheating(): Boolean {
        return getBatteryTemperature() >= 42.0f
    }
}

