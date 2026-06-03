package com.soncamedia.listeningstation.listening_station

import android.content.Context
import android.content.Intent
import android.content.BroadcastReceiver

class UsbDeviceReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // Do nothing, used only to associate the device filter for auto-granting USB permissions
    }
}
