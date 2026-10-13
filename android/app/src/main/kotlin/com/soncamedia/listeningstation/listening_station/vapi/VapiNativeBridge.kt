package com.soncamedia.listeningstation.listening_station.vapi

import ai.vapi.android.Vapi
import ai.vapi.android.VapiMessage
import ai.vapi.android.VapiMessageContent
import android.content.Context
import androidx.lifecycle.Lifecycle
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.util.Log

class VapiNativeBridge(
    private val context: Context,
    private val lifecycle: Lifecycle
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private var vapiClient: Vapi? = null
    private var eventSink: EventChannel.EventSink? = null
    private val scope = CoroutineScope(Dispatchers.Main + Job())
    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var eventsJob: Job? = null

    init {
        // Lazy initialization: Vapi will be initialized on demand when startCall is invoked
    }

    fun initVapi() {
        isDailyListenerAttached = false
        lastRawTranscriptText = null
        if (vapiClient == null) {
            try {
                Log.d("VapiNativeBridge", "Creating fresh Vapi client instance with public key: ${VapiConfig.PUBLIC_KEY}")
                vapiClient = Vapi(
                    context = context,
                    lifecycle = lifecycle,
                    configuration = Vapi.Configuration(publicKey = VapiConfig.PUBLIC_KEY)
                )
                observeVapiEvents()
            } catch (e: Exception) {
                Log.e("VapiNativeBridge", "Error creating Vapi client instance: $e")
            }
        }
    }

    private fun observeVapiEvents() {
        val client = vapiClient ?: return
        eventsJob?.cancel()
        eventsJob = scope.launch {
            client.eventFlow.collect { event ->
                Log.d("VapiNativeBridge", "Received Vapi Event: $event")
                handleVapiEvent(event)
            }
        }
    }

    @Volatile
    private var isMuted = false

    fun applyWebRtcMute(mute: Boolean) {
        isMuted = mute
        Log.d("VapiNativeBridge", "applyWebRtcMute: mute=$mute")

        // 1. Static call trên legacy WebRtcAudioTrack (org.webrtc.voiceengine.WebRtcAudioTrack)
        try {
            val cls = Class.forName("org.webrtc.voiceengine.WebRtcAudioTrack")
            val method = cls.getMethod("setSpeakerMute", Boolean::class.javaPrimitiveType)
            method.invoke(null, mute)
            Log.d("VapiNativeBridge", "Invoked static org.webrtc.voiceengine.WebRtcAudioTrack.setSpeakerMute($mute)")
        } catch (e: Throwable) {}

        if (!mute) {
            // Khi BẬT TIẾNG: chỉ cần static unmute là đủ, TUYỆT ĐỐI không quét reflection hay quét Threads
            // để tránh tạm dừng luồng âm thanh WebRTC gây khựng/giật tiếng (audio stutter).
            return
        }

        // 2. Chỉ khi mute=true (TẮT TIẾNG HOÀN TOÀN), quét client để hạ volume AudioTrack
        try {
            val client = vapiClient
            if (client != null) {
                muteFieldsOfObject(client, mute)
                try {
                    val callField = client.javaClass.getDeclaredField("call")
                    callField.isAccessible = true
                    val callClient = callField.get(client)
                    if (callClient != null) {
                        muteFieldsOfObject(callClient, mute)
                    }
                } catch (e: Throwable) {}
            }
        } catch (e: Throwable) {}
    }

    private fun setVapiClientMuted(muted: Boolean) {
        try {
            val client = vapiClient ?: return
            for (m in client.javaClass.declaredMethods) {
                if (m.name.startsWith("setMuted")) {
                    m.isAccessible = true
                    m.invoke(client, muted)
                    Log.d("VapiNativeBridge", "Invoked vapiClient.setMuted($muted) via reflection")
                    return
                }
            }
        } catch (e: Throwable) {
            Log.w("VapiNativeBridge", "Error invoking setMuted on vapiClient: $e")
        }
    }

    private fun muteFieldsOfObject(obj: Any, mute: Boolean) {
        try {
            var currClass: Class<*>? = obj.javaClass
            while (currClass != null && currClass != Any::class.java) {
                for (f in currClass.declaredFields) {
                    try {
                        f.isAccessible = true
                        val value = f.get(obj) ?: continue

                        // Nếu là AudioTrack phần cứng
                        if (value is android.media.AudioTrack) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                value.setVolume(if (mute) 0.0f else 1.0f)
                            } else {
                                @Suppress("DEPRECATION")
                                value.setStereoVolume(if (mute) 0.0f else 1.0f, if (mute) 0.0f else 1.0f)
                            }
                            Log.d("VapiNativeBridge", "Applied AudioTrack.setVolume: ${if (mute) 0.0f else 1.0f}")
                        }

                        // Nếu field là WebRtcAudioTrack
                        val valClassName = value.javaClass.name
                        if (valClassName.contains("WebRtcAudioTrack")) {
                            try {
                                val m = value.javaClass.getMethod("setSpeakerMute", Boolean::class.javaPrimitiveType)
                                m.invoke(value, mute)
                                Log.d("VapiNativeBridge", "Invoked setSpeakerMute($mute) on $valClassName")
                            } catch (e: Throwable) {}

                            // Lấy AudioTrack bên trong WebRtcAudioTrack nếu có
                            try {
                                val atField = value.javaClass.getDeclaredField("audioTrack")
                                atField.isAccessible = true
                                val track = atField.get(value) as? android.media.AudioTrack
                                if (track != null) {
                                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                        track.setVolume(if (mute) 0.0f else 1.0f)
                                    } else {
                                        @Suppress("DEPRECATION")
                                        track.setStereoVolume(if (mute) 0.0f else 1.0f, if (mute) 0.0f else 1.0f)
                                    }
                                    Log.d("VapiNativeBridge", "Applied track.setVolume inside $valClassName: ${if (mute) 0.0f else 1.0f}")
                                }
                            } catch (e: Throwable) {}
                        }
                    } catch (e: Throwable) {}
                }
                currClass = currClass.superclass
            }
        } catch (e: Throwable) {}
    }

    fun syncVoiceCallVolumeToMusic() {
        try {
            val musicVol = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            val maxMusic = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            val maxVoice = audioManager.getStreamMaxVolume(AudioManager.STREAM_VOICE_CALL)

            // Kiểm tra trạng thái MUTE của STREAM_MUSIC
            val isMusicMuted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                try {
                    audioManager.isStreamMute(AudioManager.STREAM_MUSIC)
                } catch (e: Exception) {
                    musicVol <= 0
                }
            } else {
                musicVol <= 0
            }

            if (musicVol <= 0 || isMusicMuted) {
                // Mức 0 (hoặc khi hệ thống bấm MUTE): TẮT TIẾNG HOÀN TOÀN (DEAD SILENT)
                Log.d("VapiNativeBridge", "syncVoiceCallVolumeToMusic: musicVol=$musicVol, isMusicMuted=$isMusicMuted -> SILENCE / MUTE voice call")

                // 1. Can thiệp trực tiếp WebRTC & AudioTrack hardware buffer (Tắt hẳn tiếng digital)
                applyWebRtcMute(true)

                // 2. Tắt đường phát loa ngoài (ngắt phần cứng loa ngoài)
                try {
                    audioManager.isSpeakerphoneOn = false
                } catch (e: Exception) {
                    Log.w("VapiNativeBridge", "Cannot set isSpeakerphoneOn=false: $e")
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    try {
                        audioManager.clearCommunicationDevice()
                    } catch (e: Exception) {}
                }

                // 3. Đưa âm lượng STREAM_VOICE_CALL về mức tối thiểu
                try {
                    audioManager.setStreamVolume(AudioManager.STREAM_VOICE_CALL, 0, 0)
                } catch (e: Exception) {}

                // 4. Kích hoạt cờ MUTE cho STREAM_VOICE_CALL nếu hệ thống hỗ trợ
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    try {
                        audioManager.adjustStreamVolume(AudioManager.STREAM_VOICE_CALL, AudioManager.ADJUST_MUTE, 0)
                    } catch (e: Exception) {
                        Log.w("VapiNativeBridge", "Cannot adjustStreamVolume MUTE: $e")
                    }
                }
            } else {
                // Âm lượng > 0: BẬT TIẾNG TRỞ LẠI
                // 1. Mở lại loa ngoài
                try {
                    audioManager.isSpeakerphoneOn = true
                } catch (e: Exception) {
                    Log.w("VapiNativeBridge", "Cannot set isSpeakerphoneOn=true: $e")
                }

                // 2. Đảm bảo micro KHÔNG bị mute phần cứng
                try {
                    audioManager.isMicrophoneMute = false
                } catch (e: Exception) {
                    Log.w("VapiNativeBridge", "Cannot unmute microphone: $e")
                }

                // 3. Xử lý thiết bị giao tiếp âm thanh trên Android 12+ (API 31+)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    try {
                        // Luôn clearCommunicationDevice() để hệ thống Android tự động định tuyến
                        // microphone sang thiết bị ngoại vi/USB mic đang cắm, TUYỆT ĐỐI không ép sang TYPE_BUILTIN_SPEAKER
                        // vì sẽ vô tình ngắt kết nối micro USB trên Android Box / TV.
                        audioManager.clearCommunicationDevice()
                        Log.d("VapiNativeBridge", "clearCommunicationDevice() applied to keep USB mic active")
                    } catch (e: Exception) {
                        Log.w("VapiNativeBridge", "Error clearing communication device: $e")
                    }
                }

                // 4. Bỏ cờ MUTE
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    try {
                        audioManager.adjustStreamVolume(AudioManager.STREAM_VOICE_CALL, AudioManager.ADJUST_UNMUTE, 0)
                    } catch (e: Exception) {
                        Log.w("VapiNativeBridge", "Cannot adjustStreamVolume UNMUTE: $e")
                    }
                }

                // 5. Mở lại luồng WebRTC & AudioTrack
                applyWebRtcMute(false)

                // 4. Đặt mức âm lượng tương ứng [minAudibleVoice .. maxVoice]
                val minAudibleVoice = if (maxVoice >= 3) 2 else 1
                val targetVoiceVol = if (maxMusic > 1 && maxVoice > minAudibleVoice) {
                    val fraction = (musicVol - 1).toFloat() / (maxMusic - 1).toFloat()
                    minAudibleVoice + Math.round(fraction * (maxVoice - minAudibleVoice).toFloat()).toInt()
                } else {
                    minAudibleVoice
                }

                val finalVoiceVol = Math.max(minAudibleVoice, Math.min(targetVoiceVol, maxVoice))

                Log.d("VapiNativeBridge", "syncVoiceCallVolumeToMusic: musicVol=$musicVol/$maxMusic -> finalVoiceVol=$finalVoiceVol/$maxVoice (minAudible=$minAudibleVoice, speakerOn=true)")
                audioManager.setStreamVolume(AudioManager.STREAM_VOICE_CALL, finalVoiceVol, 0)
            }
        } catch (e: Exception) {
            Log.e("VapiNativeBridge", "Error syncing voice call volume: $e")
        }
    }

    fun ensureMicrophoneEnabled() {
        try {
            audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
            audioManager.isMicrophoneMute = false
            audioManager.isSpeakerphoneOn = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                audioManager.clearCommunicationDevice()
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val inputDevices = audioManager.getDevices(AudioManager.GET_DEVICES_INPUTS)
                Log.d("VapiNativeBridge", "ensureMicrophoneEnabled: active input devices (${inputDevices.size}):")
                for (dev in inputDevices) {
                    Log.d("VapiNativeBridge", "  -> Input: id=${dev.id}, type=${dev.type}, name=${dev.productName}")
                }
            }

            setVapiClientMuted(false)

            val client = vapiClient ?: return
            val callField = Vapi::class.java.getDeclaredField("call")
            callField.isAccessible = true
            val dailyCall = callField.get(client) ?: return

            var invokedInputs = false
            for (m in dailyCall.javaClass.methods) {
                if (m.name == "setInputsEnabled") {
                    m.isAccessible = true
                    val paramTypes = m.parameterTypes
                    if (paramTypes.size == 3) {
                        m.invoke(dailyCall, java.lang.Boolean.FALSE, java.lang.Boolean.TRUE, null)
                        Log.d("VapiNativeBridge", "Invoked dailyCall.setInputsEnabled(camera=false, microphone=true, null)")
                        invokedInputs = true
                        break
                    } else if (paramTypes.size == 2) {
                        m.invoke(dailyCall, java.lang.Boolean.FALSE, java.lang.Boolean.TRUE)
                        Log.d("VapiNativeBridge", "Invoked dailyCall.setInputsEnabled(camera=false, microphone=true)")
                        invokedInputs = true
                        break
                    }
                }
            }
            if (!invokedInputs) {
                Log.d("VapiNativeBridge", "dailyCall (${dailyCall.javaClass.name}) did not have 2/3 arg setInputsEnabled")
            }
        } catch (e: Throwable) {
            Log.w("VapiNativeBridge", "ensureMicrophoneEnabled exception: $e")
        }
    }

    private var isDailyListenerAttached = false
    private var lastRawTranscriptText: String? = null
    private var lastRawTranscriptTime: Long = 0L
    @Volatile
    private var lastActiveRole: String = ""

    fun attachDailyListener() {
        val client = vapiClient ?: return
        if (isDailyListenerAttached) return
        try {
            val callField = Vapi::class.java.getDeclaredField("call")
            callField.isAccessible = true
            val dailyCall = callField.get(client) ?: return

            val listenerClass = Class.forName("co.daily.CallClientListener")
            val proxy = java.lang.reflect.Proxy.newProxyInstance(
                listenerClass.classLoader,
                arrayOf(listenerClass)
            ) { _, method, args ->
                val mName = method.name
                if (mName == "onAppMessage" && args != null && args.isNotEmpty()) {
                    val rawJson = args[0] as? String
                    if (!rawJson.isNullOrBlank()) {
                        scope.launch(Dispatchers.Main) {
                            handleRawAppMessage(rawJson)
                        }
                    }
                } else if (mName == "onLocalAudioLevel" && args != null && args.isNotEmpty()) {
                    val level = (args[0] as? Number)?.toFloat() ?: 0f
                    if (level > 0.05f) {
                        Log.d("VapiNativeBridge", "WebRTC Local Mic Audio Level: $level")
                    }
                } else if (mName == "onInputsUpdated") {
                    Log.d("VapiNativeBridge", "WebRTC onInputsUpdated: ${args?.firstOrNull()}")
                }

                if (method.returnType == java.lang.Boolean.TYPE) return@newProxyInstance false
                if (method.returnType == java.lang.Integer.TYPE) return@newProxyInstance 0
                if (method.returnType == java.lang.Long.TYPE) return@newProxyInstance 0L
                if (method.returnType == java.lang.Float.TYPE) return@newProxyInstance 0.0f
                if (method.returnType == java.lang.Double.TYPE) return@newProxyInstance 0.0
                return@newProxyInstance null
            }
            val addListenerMethod = dailyCall.javaClass.getMethod("addListener", listenerClass)
            addListenerMethod.invoke(dailyCall, proxy)
            isDailyListenerAttached = true
            Log.d("VapiNativeBridge", "Successfully attached dynamic CallClientListener to intercept raw WebRTC Vapi messages!")
        } catch (e: Throwable) {
            Log.w("VapiNativeBridge", "Could not attach dynamic CallClientListener: $e")
        }
    }

    private fun handleRawAppMessage(rawJson: String) {
        val sink = eventSink ?: return
        try {
            val json = org.json.JSONObject(rawJson)
            val type = json.optString("type")
            when (type) {
                "transcript" -> {
                    val role = json.optString("role") // "assistant" or "user"
                    val transcriptType = json.optString("transcriptType") // "partial" or "final"
                    val text = if (json.has("transcript")) json.optString("transcript") else json.optString("text")
                    if (role.isNotBlank()) {
                        lastActiveRole = role
                    }
                    if (!text.isNullOrBlank()) {
                        lastRawTranscriptText = text.trim()
                        lastRawTranscriptTime = System.currentTimeMillis()
                        Log.d("VapiNativeBridge", "Raw transcript intercepted: role='$role', type='$transcriptType', text='$text'")
                        val data = mapOf(
                            "event" to "transcript",
                            "text" to text,
                            "transcriptType" to transcriptType,
                            "role" to role,
                            "raw" to rawJson
                        )
                        sink.success(data)
                    }
                }
                "conversation-update" -> {
                    val messagesArray = json.optJSONArray("messages")
                    if (messagesArray != null) {
                        val messages = mutableListOf<Map<String, String>>()
                        for (i in 0 until messagesArray.length()) {
                            val msgObj = messagesArray.optJSONObject(i) ?: continue
                            val role = msgObj.optString("role", "user")
                            val content = if (msgObj.has("message")) msgObj.optString("message") else msgObj.optString("content")
                            if (!content.isNullOrBlank()) {
                                messages.add(mapOf("role" to role, "content" to content))
                            }
                        }
                        Log.d("VapiNativeBridge", "Raw conversation-update intercepted: ${messages.size} messages")
                        val data = mapOf(
                            "event" to "conversationUpdate",
                            "messages" to messages
                        )
                        sink.success(data)
                    }
                }
                "speech-update" -> {
                    val status = json.optString("status") // "started" or "stopped"
                    val role = json.optString("role") // "assistant" or "user"
                    val text = json.optString("text")
                    if (role.isNotBlank()) {
                        lastActiveRole = role
                    }
                    Log.d("VapiNativeBridge", "Raw speech-update intercepted: status='$status', role='$role', text='$text'")
                    val data = mapOf(
                        "event" to "speechUpdate",
                        "status" to status,
                        "role" to role,
                        "text" to text
                    )
                    sink.success(data)
                }
            }
        } catch (e: Exception) {
            Log.w("VapiNativeBridge", "Error parsing raw app message: $e")
        }
    }

    private fun handleVapiEvent(event: Vapi.Event) {
        val sink = eventSink
        if (sink == null) {
            Log.w("VapiNativeBridge", "handleVapiEvent: eventSink is NULL! Cannot send event: $event")
            return
        }
        scope.launch(Dispatchers.Main) {
            when (event) {
                is Vapi.Event.CallDidStart -> {
                    Log.d("VapiNativeBridge", "CallDidStart received -> Attaching Daily listener, ensuring mic enabled & syncing volume")
                    ensureMicrophoneEnabled()
                    attachDailyListener()
                    syncVoiceCallVolumeToMusic()
                    // WebRTC audio session có thể can thiệp lại volume sau khi kết nối,
                    // re-sync sau 500ms và 1500ms để đảm bảo giữ đúng mức âm lượng
                    scope.launch {
                        delay(500)
                        ensureMicrophoneEnabled()
                        attachDailyListener()
                        syncVoiceCallVolumeToMusic()
                        delay(1000)
                        ensureMicrophoneEnabled()
                        attachDailyListener()
                        syncVoiceCallVolumeToMusic()
                    }
                    val data = mapOf("event" to "callDidStart")
                    sink.success(data)
                }
                is Vapi.Event.CallDidEnd -> {
                    val data = mapOf("event" to "callDidEnd")
                    sink.success(data)
                }
                is Vapi.Event.ConversationUpdate -> {
                    Log.d("VapiNativeBridge", "ConversationUpdate raw messages count: ${event.messages.size}, raw: ${event.messages}")
                    val messages = mutableListOf<Map<String, String>>()
                    for (msg in event.messages) {
                        try {
                            val role = (msg["role"] as? String) ?: (msg["speaker"] as? String) ?: "user"
                            val content = (msg["content"] as? String) 
                                ?: (msg["message"] as? String) 
                                ?: (msg["text"] as? String) 
                                ?: (msg["transcript"] as? String)
                            if (!content.isNullOrBlank()) {
                                messages.add(mapOf("role" to role, "content" to content))
                            }
                        } catch (e: Exception) {
                            Log.e("VapiNativeBridge", "Error parsing msg item: $e")
                        }
                    }
                    val data = mapOf(
                        "event" to "conversationUpdate",
                        "messages" to messages
                    )
                    Log.d("VapiNativeBridge", "Emitting conversationUpdate to Flutter with ${messages.size} messages")
                    sink.success(data)
                }
                is Vapi.Event.SpeechUpdate -> {
                    if (isMuted) {
                        applyWebRtcMute(true)
                    }
                    var status = ""
                    var role = ""
                    try {
                        for (f in event.javaClass.declaredFields) {
                            f.isAccessible = true
                            val fName = f.name.lowercase()
                            val fVal = f.get(event)?.toString() ?: ""
                            if (fName.contains("status")) status = fVal
                            if (fName.contains("role")) role = fVal
                        }
                    } catch (e: Exception) {}
                    val data = mapOf(
                        "event" to "speechUpdate",
                        "status" to status,
                        "role" to role,
                        "text" to (event.text ?: "")
                    )
                    Log.d("VapiNativeBridge", "SpeechUpdate: status=$status, role=$role, text=${event.text}")
                    sink.success(data)
                }
                is Vapi.Event.FunctionCall -> {
                    val data = mapOf(
                        "event" to "functionCall",
                        "name" to event.name,
                        "parameters" to event.parameters.toString()
                    )
                    sink.success(data)
                }
                is Vapi.Event.Error -> {
                    val data = mapOf(
                        "event" to "error",
                        "error" to event.error
                    )
                    sink.success(data)
                }
                is Vapi.Event.Transcript -> {
                    var text = event.text ?: ""
                    var transcriptType = ""
                    var role = ""
                    try {
                        for (f in event.javaClass.declaredFields) {
                            f.isAccessible = true
                            val value = f.get(event)
                            val fName = f.name.lowercase()
                            if (fName.contains("transcripttype") || (fName.contains("type") && transcriptType.isEmpty())) {
                                transcriptType = value?.toString() ?: ""
                            } else if (fName.contains("role") && role.isEmpty()) {
                                role = value?.toString() ?: ""
                            } else if ((fName.contains("text") || fName.contains("transcript")) && text.isEmpty()) {
                                text = value?.toString() ?: ""
                            }
                        }
                    } catch (e: Exception) {}

                    if (role.isBlank() && lastActiveRole.isNotBlank()) {
                        role = lastActiveRole
                    }

                    // Nếu raw app message vừa emit text này trong 500ms, bỏ qua để tránh trùng lặp
                    if (text.isNotBlank() && (text.trim() != lastRawTranscriptText || System.currentTimeMillis() - lastRawTranscriptTime > 500)) {
                        val data = mapOf(
                            "event" to "transcript",
                            "text" to text,
                            "transcriptType" to transcriptType,
                            "role" to role,
                            "raw" to event.toString()
                        )
                        sink.success(data)
                    }
                }
                else -> {
                    val className = event.javaClass.simpleName
                    val data = mapOf(
                        "event" to "genericEvent",
                        "info" to "$className: $event"
                    )
                    sink.success(data)
                }
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startCall" -> {
                val assistantIdArg = call.argument<String>("assistantId")
                val assistantId = if (!assistantIdArg.isNullOrBlank()) assistantIdArg else VapiConfig.DEMO_ASSISTANT_ID

                scope.launch {
                    try {
                        try {
                            vapiClient?.stop()
                        } catch (e: Exception) {
                            Log.w("VapiNativeBridge", "Error stopping previous call: $e")
                        }
                        vapiClient = null
                        initVapi()

                        val client = vapiClient
                        if (client == null) {
                            result.error("VAPI_ERROR", "Vapi client is null", null)
                            return@launch
                        }

                        Log.d("VapiNativeBridge", "Starting Vapi call with assistantId: $assistantId (100% Vapi Dashboard setup)")
                        syncVoiceCallVolumeToMusic()

                        val res = client.start(assistantId = assistantId)
                        res.onSuccess {
                            Log.d("VapiNativeBridge", "client.start successful")
                            ensureMicrophoneEnabled()
                            attachDailyListener()
                            syncVoiceCallVolumeToMusic()
                            result.success(true)
                        }.onFailure { error ->
                            Log.e("VapiNativeBridge", "client.start failed: ${error.message}")
                            result.error("VAPI_ERROR", error.message ?: "Failed to start Vapi call", null)
                        }
                    } catch (e: Exception) {
                        Log.e("VapiNativeBridge", "Exception starting Vapi call: $e")
                        result.error("VAPI_ERROR", e.message ?: "Exception starting Vapi call", null)
                    }
                }
            }
            "stopCall" -> {
                Log.d("VapiNativeBridge", "stopCall requested -> Stopping Vapi WebRTC client")
                isDailyListenerAttached = false
                lastRawTranscriptText = null
                try {
                    vapiClient?.stop()
                } catch (e: Exception) {
                    Log.e("VapiNativeBridge", "Error stopping vapi: $e")
                }
                vapiClient = null
                try {
                    audioManager.mode = AudioManager.MODE_NORMAL
                } catch (e: Exception) {
                    Log.w("VapiNativeBridge", "Error resetting audioManager mode: $e")
                }
                result.success(true)
            }
            "syncVolume" -> {
                Log.d("VapiNativeBridge", "syncVolume requested from Flutter")
                syncVoiceCallVolumeToMusic()
                result.success(true)
            }
            "setMuted" -> {
                val muted = call.argument<Boolean>("muted") ?: false
                Log.d("VapiNativeBridge", "setMuted requested from Flutter: $muted")
                applyWebRtcMute(muted)
                setVapiClientMuted(muted)
                result.success(true)
            }
            "setSpeakerMuted" -> {
                val muted = call.argument<Boolean>("muted") ?: false
                Log.d("VapiNativeBridge", "setSpeakerMuted requested from Flutter: $muted (speaker only, microphone stays active)")
                applyWebRtcMute(muted)
                result.success(true)
            }
            "sendMessage" -> {
                val message = call.argument<String>("message") ?: ""
                Log.d("VapiNativeBridge", "sendMessage requested: '$message'")
                scope.launch {
                    try {
                        val client = vapiClient
                        if (client != null && message.isNotBlank()) {
                            val vapiMsg = VapiMessage(
                                type = "add-message",
                                message = VapiMessageContent(
                                    role = "user",
                                    content = message
                                )
                            )
                            val res = client.send(vapiMsg)
                            Log.d("VapiNativeBridge", "client.send result: $res")
                            result.success(true)
                        } else {
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        Log.e("VapiNativeBridge", "Error sending message to Vapi: $e")
                        result.success(false)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        Log.d("VapiNativeBridge", "EventChannel onListen - Flutter is now listening to events")
        this.eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        Log.d("VapiNativeBridge", "EventChannel onCancel - Flutter stopped listening to events")
        this.eventSink = null
    }

    fun cleanUp() {
        try {
            vapiClient?.stop()
        } catch (e: Exception) {
            Log.e("VapiNativeBridge", "Error stopping vapi in cleanUp: $e")
        }
        vapiClient = null
        try {
            audioManager.mode = AudioManager.MODE_NORMAL
        } catch (e: Exception) {
            Log.w("VapiNativeBridge", "Error resetting audioManager mode in cleanUp: $e")
        }
    }
}
