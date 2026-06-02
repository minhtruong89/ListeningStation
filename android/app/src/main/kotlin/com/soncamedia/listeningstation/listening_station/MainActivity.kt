package com.soncamedia.listeningstation.listening_station

import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaPlayer
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.soncamedia.listeningstation/audio_devices"
    private var mediaPlayer: MediaPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAudioDevices" -> {
                    val devicesList = getConnectedAudioDevices()
                    result.success(devicesList)
                }
                "playMp3AtDevice" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val deviceIndex = call.argument<Int>("deviceIndex") ?: 0
                    val success = playMp3AtDevice(filePath, deviceIndex)
                    result.success(success)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun getConnectedAudioDevices(): Map<String, List<String>> {
        val outputs = mutableListOf<String>()
        val inputs = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val devices = audioManager.getDevices(AudioManager.GET_DEVICES_ALL)
            for (device in devices) {
                val typeName = getDeviceTypeName(device.type)
                val deviceName = "${device.productName} ($typeName)"
                
                if (device.isSink) {
                    outputs.add(deviceName)
                }
                if (device.isSource) {
                    inputs.add(deviceName)
                }
            }
        } else {
            outputs.add("Built-in Speaker")
            inputs.add("Built-in Microphone")
        }

        return mapOf(
            "outputs" to outputs,
            "inputs" to inputs
        )
    }

    private fun playMp3AtDevice(filePath: String, deviceIndex: Int): Boolean {
        try {
            mediaPlayer?.stop()
            mediaPlayer?.release()
            mediaPlayer = null

            val mp3File = java.io.File(filePath)
            if (!mp3File.exists()) {
                android.util.Log.e("AudioPlay", "File not found: $filePath")
                return false
            }

            val mp = MediaPlayer()
            mp.setDataSource(filePath)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val devices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                if (deviceIndex >= 0 && deviceIndex < devices.size) {
                    val targetDevice = devices[deviceIndex]
                    val success = mp.setPreferredDevice(targetDevice)
                    android.util.Log.d("AudioPlay", "Setting preferred device: ${targetDevice.productName}, success=$success")
                } else {
                    android.util.Log.w("AudioPlay", "Device index $deviceIndex out of bounds (0..${devices.size - 1})")
                }
            }

            mp.prepare()
            mp.start()
            mediaPlayer = mp
            return true
        } catch (e: Exception) {
            android.util.Log.e("AudioPlay", "Error playing MP3: ${e.message}", e)
            return false
        }
    }

    private fun getDeviceTypeName(type: Int): String {
        return when (type) {
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "Earpiece"
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "Speaker"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Wired Headset"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "Wired Headphones"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth SCO"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "Bluetooth A2DP"
            AudioDeviceInfo.TYPE_HDMI -> "HDMI"
            AudioDeviceInfo.TYPE_USB_ACCESSORY -> "USB Accessory"
            AudioDeviceInfo.TYPE_USB_DEVICE -> "USB Device"
            AudioDeviceInfo.TYPE_USB_HEADSET -> "USB Headset"
            AudioDeviceInfo.TYPE_TELEPHONY -> "Telephony"
            AudioDeviceInfo.TYPE_LINE_ANALOG -> "Line Analog"
            AudioDeviceInfo.TYPE_LINE_DIGITAL -> "Line Digital"
            AudioDeviceInfo.TYPE_FM -> "FM"
            AudioDeviceInfo.TYPE_AUX_LINE -> "Aux Line"
            AudioDeviceInfo.TYPE_IP -> "IP"
            AudioDeviceInfo.TYPE_BUS -> "Bus"
            AudioDeviceInfo.TYPE_HEARING_AID -> "Hearing Aid"
            else -> "Unknown"
        }
    }
}
