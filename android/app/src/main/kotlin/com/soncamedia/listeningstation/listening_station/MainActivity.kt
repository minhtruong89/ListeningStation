package com.soncamedia.listeningstation.listening_station

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.BroadcastReceiver
import android.app.PendingIntent
import android.os.Bundle
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbEndpoint
import android.hardware.usb.UsbInterface
import android.hardware.usb.UsbManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.ToneGenerator
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.soncamedia.listeningstation/audio_devices"
    private val ACTION_USB_PERMISSION = "com.soncamedia.listeningstation.USB_PERMISSION"
    private var mediaPlayer: MediaPlayer? = null
    private var usbPermissionCallback: ((Boolean) -> Unit)? = null

    // Persistent USB UART Connection Cache
    private var activeDevice: UsbDevice? = null
    private var activeConnection: UsbDeviceConnection? = null
    private var activeInterface: UsbInterface? = null
    private var inEndpoint: UsbEndpoint? = null
    private var outEndpoint: UsbEndpoint? = null

    private val usbReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (ACTION_USB_PERMISSION == intent.action) {
                synchronized(this) {
                    val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                    if (intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                        device?.let {
                            android.util.Log.d("UsbPermission", "Permission granted for device ${device.deviceName}")
                            usbPermissionCallback?.invoke(true)
                        }
                    } else {
                        android.util.Log.d("UsbPermission", "Permission denied for device ${device?.deviceName}")
                        usbPermissionCallback?.invoke(false)
                    }
                    usbPermissionCallback = null
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(usbReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(usbReceiver, filter)
        }
    }

    override fun onDestroy() {
        closeActiveUartConnection()
        unregisterReceiver(usbReceiver)
        super.onDestroy()
    }

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
                "startRecording" -> {
                    val filePath = call.argument<String>("filePath") ?: ""
                    val deviceIndex = call.argument<Int>("deviceIndex") ?: 0
                    val success = startRecording(filePath, deviceIndex)
                    result.success(success)
                }
                "stopRecording" -> {
                    val success = stopRecording()
                    result.success(success)
                }
                "getUsbSerialDevices" -> {
                    val serialDevicesList = getConnectedUsbSerialDevices()
                    result.success(serialDevicesList)
                }
                "requestUsbPermission" -> {
                    val vendorId = call.argument<Int>("vendorId") ?: 0
                    val productId = call.argument<Int>("productId") ?: 0
                    requestUsbPermission(vendorId, productId) { granted ->
                        result.success(granted)
                    }
                }
                "testUartCommunicate" -> {
                    val vendorId = call.argument<Int>("vendorId") ?: 0
                    val productId = call.argument<Int>("productId") ?: 0
                    val baudRate = call.argument<Int>("baudRate") ?: 9600
                    val testMessage = call.argument<String>("testMessage") ?: "PING\n"
                    val testResult = testUartCommunicate(vendorId, productId, baudRate, testMessage)
                    result.success(testResult)
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
            val outputDevices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            for (device in outputDevices) {
                val typeName = getDeviceTypeName(device.type)
                outputs.add("${device.productName} ($typeName)")
            }
            val inputDevices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
            for (device in inputDevices) {
                val typeName = getDeviceTypeName(device.type)
                inputs.add("${device.productName} ($typeName)")
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

    private var activeRecorder: MediaRecorder? = null

    private fun startRecording(filePath: String, deviceIndex: Int): Boolean {
        if (activeRecorder != null) {
            try {
                activeRecorder?.stop()
                activeRecorder?.release()
            } catch (e: Exception) {}
            activeRecorder = null
        }

        val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(this)
        } else {
            @Suppress("DEPRECATION")
            MediaRecorder()
        }

        try {
            val file = java.io.File(filePath)
            file.parentFile?.mkdirs()

            recorder.setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            recorder.setAudioSamplingRate(16000)
            recorder.setAudioEncodingBitRate(32000)
            recorder.setAudioChannels(1)
            recorder.setOutputFile(filePath)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val devices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
                if (deviceIndex >= 0 && deviceIndex < devices.size) {
                    val targetDevice = devices[deviceIndex]
                    val success = recorder.setPreferredDevice(targetDevice)
                    android.util.Log.d("AudioRecord", "Setting preferred input device: ${targetDevice.productName}, success=$success")
                } else {
                    android.util.Log.w("AudioRecord", "Device index $deviceIndex out of bounds (0..${devices.size - 1})")
                }
            }

            recorder.prepare()
            recorder.start()
            activeRecorder = recorder
            android.util.Log.d("AudioRecord", "Recording started successfully on device $deviceIndex")
            return true
        } catch (e: Exception) {
            android.util.Log.e("AudioRecord", "Error during recording setup: ${e.message}", e)
            try {
                recorder.release()
            } catch (ex: Exception) {}
            return false
        }
    }

    private fun stopRecording(): Boolean {
        val recorder = activeRecorder
        if (recorder == null) {
            android.util.Log.w("AudioRecord", "stopRecording called but activeRecorder is null")
            return false
        }
        try {
            recorder.stop()
            recorder.release()
            activeRecorder = null
            android.util.Log.d("AudioRecord", "Recording stopped and released successfully")
            return true
        } catch (e: Exception) {
            android.util.Log.e("AudioRecord", "Error stopping recorder: ${e.message}", e)
            try {
                recorder.release()
            } catch (ex: Exception) {}
            activeRecorder = null
            return false
        }
    }

    private fun getConnectedUsbSerialDevices(): List<Map<String, Any>> {
        val list = mutableListOf<Map<String, Any>>()
        val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        val deviceList = usbManager.deviceList
        for (device in deviceList.values) {
            if (isUsbSerialDevice(device)) {
                val map = mapOf(
                    "name" to (device.productName ?: "USB Serial Device"),
                    "vendorId" to device.vendorId,
                    "productId" to device.productId,
                    "hasPermission" to usbManager.hasPermission(device)
                )
                list.add(map)
            }
        }
        return list
    }

    private fun isUsbSerialDevice(device: UsbDevice): Boolean {
        val vid = device.vendorId
        if (vid == 0x1A86 || // CH340 / CH341
            vid == 0x10C4 || // CP210x
            vid == 0x0403 || // FTDI
            vid == 0x067B || // PL2303
            vid == 0x2341 || // Arduino Uno
            device.deviceClass == UsbConstants.USB_CLASS_COMM) {
            return true
        }
        return false
    }

    private fun requestUsbPermission(vendorId: Int, productId: Int, callback: (Boolean) -> Unit) {
        val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        val deviceList = usbManager.deviceList
        var targetDevice: UsbDevice? = null
        for (device in deviceList.values) {
            if (device.vendorId == vendorId && device.productId == productId) {
                targetDevice = device
                break
            }
        }

        if (targetDevice == null) {
            callback(false)
            return
        }

        if (usbManager.hasPermission(targetDevice)) {
            callback(true)
            return
        }

        usbPermissionCallback = callback
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
        val permissionIntent = PendingIntent.getBroadcast(
            this, 0, Intent(ACTION_USB_PERMISSION), flags
        )
        usbManager.requestPermission(targetDevice, permissionIntent)
    }

    private fun getUartEndpointsAndConnection(targetDevice: UsbDevice): Boolean {
        if (activeConnection != null && activeDevice == targetDevice) {
            return true
        }

        closeActiveUartConnection()

        val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        val connection = usbManager.openDevice(targetDevice) ?: return false
        val usbInterface = targetDevice.getInterface(0)

        if (!connection.claimInterface(usbInterface, true)) {
            connection.close()
            return false
        }

        var inEp: UsbEndpoint? = null
        var outEp: UsbEndpoint? = null
        for (i in 0 until usbInterface.endpointCount) {
            val ep = usbInterface.getEndpoint(i)
            if (ep.type == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                if (ep.direction == UsbConstants.USB_DIR_IN) {
                    inEp = ep
                } else if (ep.direction == UsbConstants.USB_DIR_OUT) {
                    outEp = ep
                }
            }
        }

        if (inEp == null || outEp == null) {
            connection.releaseInterface(usbInterface)
            connection.close()
            return false
        }

        activeDevice = targetDevice
        activeConnection = connection
        activeInterface = usbInterface
        inEndpoint = inEp
        outEndpoint = outEp

        // Initialize baud rate on connection setup
        val vid = targetDevice.vendorId
        val baudRate = 9600
        if (vid == 0x10C4) {
            connection.controlTransfer(0x41, 0x00, 0x0001, 0, null, 0, 1000)
            val baudRateBytes = byteArrayOf(
                (baudRate and 0xFF).toByte(),
                ((baudRate shr 8) and 0xFF).toByte(),
                ((baudRate shr 16) and 0xFF).toByte(),
                ((baudRate shr 24) and 0xFF).toByte()
            )
            connection.controlTransfer(0x40, 0x1E, 0, 0, baudRateBytes, baudRateBytes.size, 1000)
        } else if (vid == 0x1A86) {
            connection.controlTransfer(0x40, 0xA1, 0xC29C, 0xB2C9, null, 0, 1000)
            connection.controlTransfer(0x40, 0xA4, 0xDF00, 0, null, 0, 1000)
            val divisorVal = 0x0050
            connection.controlTransfer(0x40, 0x9A, 0x2518, divisorVal, null, 0, 1000)
            connection.controlTransfer(0x40, 0xA4, 0xFF7F, 0, null, 0, 1000)
        } else if (targetDevice.deviceClass == UsbConstants.USB_CLASS_COMM) {
            val lineCoding = byteArrayOf(
                (baudRate and 0xFF).toByte(),
                ((baudRate shr 8) and 0xFF).toByte(),
                ((baudRate shr 16) and 0xFF).toByte(),
                ((baudRate shr 24) and 0xFF).toByte(),
                0.toByte(),
                0.toByte(),
                8.toByte()
            )
            connection.controlTransfer(0x21, 0x20, 0, 0, lineCoding, lineCoding.size, 1000)
            connection.controlTransfer(0x21, 0x22, 0x3, 0, null, 0, 1000)
        }

        return true
    }

    private fun closeActiveUartConnection() {
        try {
            activeInterface?.let {
                activeConnection?.releaseInterface(it)
            }
            activeConnection?.close()
        } catch (e: Exception) {
            android.util.Log.e("UsbUart", "Error closing connection: ${e.message}")
        } finally {
            activeConnection = null
            activeInterface = null
            activeDevice = null
            inEndpoint = null
            outEndpoint = null
        }
    }

    private fun testUartCommunicate(vendorId: Int, productId: Int, baudRate: Int, testMessage: String): Map<String, Any> {
        val response = mutableMapOf<String, Any>()
        response["success"] = false

        val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
        val deviceList = usbManager.deviceList
        var targetDevice: UsbDevice? = null
        for (device in deviceList.values) {
            if (device.vendorId == vendorId && device.productId == productId) {
                targetDevice = device
                break
            }
        }

        if (targetDevice == null) {
            response["message"] = "Device with VID: $vendorId, PID: $productId not found"
            return response
        }

        if (!usbManager.hasPermission(targetDevice)) {
            response["message"] = "No permission to access device. Request permission first."
            return response
        }

        if (!getUartEndpointsAndConnection(targetDevice)) {
            response["message"] = "Failed to open or claim USB interface."
            return response
        }

        val conn = activeConnection
        val outEp = outEndpoint
        val inEp = inEndpoint

        if (conn == null || outEp == null || inEp == null) {
            response["message"] = "Active UART connection is null."
            return response
        }

        try {
            val sendBytes = testMessage.toByteArray(Charsets.UTF_8)
            val sentLen = conn.bulkTransfer(outEp, sendBytes, sendBytes.size, 1000)
            response["sent"] = sentLen

            val readBuf = ByteArray(1024)
            val readLen = conn.bulkTransfer(inEp, readBuf, readBuf.size, 1000)
            if (readLen > 0) {
                val receivedData = String(readBuf, 0, readLen, Charsets.UTF_8)
                response["received"] = receivedData
                response["success"] = true
                response["message"] = "UART Write/Read success."
            } else {
                response["received"] = ""
                response["success"] = true
                response["message"] = "UART Write success, but Read timed out (no incoming bytes)."
            }
        } catch (e: Exception) {
            response["message"] = "Error communicating with USB Serial device: ${e.message}"
            closeActiveUartConnection() // Reset connection state on communication error
        }

        return response
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
