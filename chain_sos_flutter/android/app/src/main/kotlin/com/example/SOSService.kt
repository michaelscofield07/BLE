package com.example.chain_sos_flutter

import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log

class SOSService : Service() {

    override fun onCreate() {
        super.onCreate()
        Log.d("ChainSOS-Service", "SOSService created")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d("ChainSOS-Service", "SOSService started")
        // Later: start foreground + background work
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d("ChainSOS-Service", "SOSService destroyed")
    }

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
}
