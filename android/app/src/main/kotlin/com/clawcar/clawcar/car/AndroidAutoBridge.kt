package com.clawcar.clawcar.car

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/// Platform channel bridge between Flutter and native Android Auto.
///
/// Handles MethodChannel calls from Flutter (isAvailable, updateState, updateStatusText)
/// and sends events back to Flutter via EventChannel (voice actions, connection state).
object AndroidAutoBridge {

    private const val METHOD_CHANNEL = "com.clawcar/android_auto"
    private const val EVENT_CHANNEL = "com.clawcar/android_auto_events"

    private val mainHandler = Handler(Looper.getMainLooper())

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private var currentState: String = "disconnected"
    private var currentStatusText: String = ""
    private var isCarConnected: Boolean = false

    fun register(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        methodChannel = MethodChannel(messenger, METHOD_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(isCarConnected)
                    "updateState" -> {
                        val state = call.argument<String>("state")
                        if (state != null) {
                            currentState = state
                            ClawCarSession.activeScreen?.onStateUpdated(state)
                            result.success(null)
                        } else {
                            result.error("INVALID_ARGUMENT", "state is required", null)
                        }
                    }
                    "updateStatusText" -> {
                        val text = call.argument<String>("text")
                        if (text != null) {
                            currentStatusText = text
                            ClawCarSession.activeScreen?.onStatusTextUpdated(text)
                            result.success(null)
                        } else {
                            result.error("INVALID_ARGUMENT", "text is required", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }

        eventChannel = EventChannel(messenger, EVENT_CHANNEL).apply {
            setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })
        }
    }

    fun unregister() {
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        eventSink = null
    }

    fun sendEvent(type: String, data: Map<String, Any?>? = null) {
        val event: Map<String, Any?> = if (data != null) {
            mapOf("type" to type, "data" to data)
        } else {
            mapOf("type" to type)
        }
        mainHandler.post { eventSink?.success(event) }
    }

    fun onCarConnected() {
        isCarConnected = true
        sendEvent("connected")
    }

    fun onCarDisconnected() {
        isCarConnected = false
        currentState = "disconnected"
        sendEvent("disconnected")
    }

    fun getCurrentState(): String = currentState
    fun getCurrentStatusText(): String = currentStatusText
}
