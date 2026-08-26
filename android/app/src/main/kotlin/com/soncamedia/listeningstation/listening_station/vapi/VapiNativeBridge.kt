package com.soncamedia.listeningstation.listening_station.vapi

import ai.vapi.android.Vapi
import ai.vapi.android.VapiMessage
import ai.vapi.android.VapiMessageContent
import android.content.Context
import androidx.lifecycle.Lifecycle
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

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

    private fun handleVapiEvent(event: Vapi.Event) {
        val sink = eventSink
        if (sink == null) {
            Log.w("VapiNativeBridge", "handleVapiEvent: eventSink is NULL! Cannot send event: $event")
            return
        }
        scope.launch(Dispatchers.Main) {
            when (event) {
                is Vapi.Event.CallDidStart -> {
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
                    val data = mapOf(
                        "event" to "speechUpdate",
                        "text" to (event.text ?: "")
                    )
                    Log.d("VapiNativeBridge", "SpeechUpdate: text=${event.text}")
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
                    // Trích xuất toàn bộ fields và methods từ Transcript event
                    var text = ""
                    var transcriptType = ""
                    var role = ""
                    val rawData = mutableMapOf<String, Any?>()
                    try {
                        for (f in event.javaClass.declaredFields) {
                            f.isAccessible = true
                            val value = f.get(event)
                            val fName = f.name
                            rawData[fName] = value
                            val lower = fName.lowercase()
                            if (lower.contains("transcripttype") || (lower.contains("type") && transcriptType.isEmpty())) {
                                transcriptType = value?.toString() ?: ""
                            } else if (lower.contains("role") && role.isEmpty()) {
                                role = value?.toString() ?: ""
                            } else if ((lower.contains("text") || lower.contains("transcript")) && text.isEmpty()) {
                                text = value?.toString() ?: ""
                            }
                        }

                        // Nếu role vẫn rỗng, thử phân tích chuỗi toString() của Transcript
                        val eventStr = event.toString()
                        if (role.isEmpty()) {
                            val roleMatch = Regex("role[=:]\\s*([a-zA-Z0-9_]+)", RegexOption.IGNORE_CASE).find(eventStr)
                            if (roleMatch != null) {
                                role = roleMatch.groupValues[1]
                            }
                        }
                        if (transcriptType.isEmpty()) {
                            val typeMatch = Regex("type[=:]\\s*([a-zA-Z0-9_]+)", RegexOption.IGNORE_CASE).find(eventStr)
                            if (typeMatch != null) {
                                transcriptType = typeMatch.groupValues[1]
                            }
                        }
                        if (text.isEmpty()) {
                            val textMatch = Regex("text[=:]\\s*([^,)]+)", RegexOption.IGNORE_CASE).find(eventStr)
                            if (textMatch != null) {
                                text = textMatch.groupValues[1]
                            }
                        }
                    } catch (e: Exception) {
                        Log.e("VapiNativeBridge", "Error extracting Transcript: $e")
                    }

                    Log.d("VapiNativeBridge", "Transcript raw: role='$role', type='$transcriptType', text='$text', rawEvent=$event")
                    if (text.isNotBlank()) {
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

                        Log.d("VapiNativeBridge", "Starting Vapi call with assistantId: $assistantId")
                        val res = client.start(assistantId = assistantId)
                        res.onSuccess {
                            Log.d("VapiNativeBridge", "client.start successful")
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
                try {
                    vapiClient?.stop()
                } catch (e: Exception) {
                    Log.e("VapiNativeBridge", "Error stopping vapi: $e")
                }
                vapiClient = null
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
        vapiClient?.stop()
        vapiClient = null
    }
}
