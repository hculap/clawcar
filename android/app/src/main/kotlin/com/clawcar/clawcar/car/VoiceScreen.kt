package com.clawcar.clawcar.car

import androidx.car.app.CarContext
import androidx.car.app.Screen
import androidx.car.app.model.Action
import androidx.car.app.model.CarIcon
import androidx.car.app.model.MessageTemplate
import androidx.car.app.model.Template
import androidx.core.graphics.drawable.IconCompat

/// Main voice interaction screen for Android Auto.
///
/// Displays the current pipeline state (idle, listening, processing, speaking)
/// with a microphone action button. Tapping the mic sends a voice action event
/// to Flutter via the platform channel bridge.
class VoiceScreen(carContext: CarContext) : Screen(carContext) {

    private var state: String = "idle"
    private var statusText: String = "Tap mic to speak"

    override fun onGetTemplate(): Template {
        val title = when (state) {
            "listening" -> "Listening..."
            "processing" -> "Processing..."
            "speaking" -> "Speaking..."
            "error" -> "Error"
            else -> "ClawCar"
        }

        val micIcon = IconCompat.createWithResource(
            carContext,
            android.R.drawable.ic_btn_speak_now
        )

        val micAction = Action.Builder()
            .setIcon(CarIcon.Builder(micIcon).build())
            .setOnClickListener { onMicTapped() }
            .build()

        return MessageTemplate.Builder(statusText)
            .setTitle(title)
            .addAction(micAction)
            .setHeaderAction(Action.APP_ICON)
            .build()
    }

    fun onStateUpdated(newState: String) {
        state = newState
        statusText = when (newState) {
            "listening" -> "Listening..."
            "processing" -> "Processing your request..."
            "speaking" -> "Playing response..."
            "error" -> "Something went wrong. Tap mic to retry."
            else -> "Tap mic to speak"
        }
        invalidate()
    }

    fun onStatusTextUpdated(text: String) {
        statusText = text
        invalidate()
    }

    private fun onMicTapped() {
        when (state) {
            "idle", "error" -> {
                AndroidAutoBridge.sendEvent("voiceAction", mapOf("action" to "startListening"))
            }
            "listening" -> {
                AndroidAutoBridge.sendEvent("voiceAction", mapOf("action" to "stopListening"))
            }
            "processing", "speaking" -> {
                AndroidAutoBridge.sendEvent("voiceAction", mapOf("action" to "cancel"))
            }
        }
    }
}
