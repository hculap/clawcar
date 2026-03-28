package com.clawcar.clawcar.car

import android.content.Intent
import androidx.car.app.Screen
import androidx.car.app.Session
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner

/// Represents a single Android Auto session. Manages the screen lifecycle
/// and notifies the Flutter bridge of connection state changes.
/// Connect/disconnect track session creation/destruction, not start/stop,
/// since sessions survive onStop/onStart cycles (screen off, app switch).
class ClawCarSession : Session() {

    companion object {
        @Volatile
        var activeScreen: VoiceScreen? = null
            private set
    }

    override fun onCreateScreen(intent: Intent): Screen {
        lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onCreate(owner: LifecycleOwner) {
                AndroidAutoBridge.onCarConnected()
            }

            override fun onDestroy(owner: LifecycleOwner) {
                activeScreen = null
                AndroidAutoBridge.onCarDisconnected()
            }
        })

        val screen = VoiceScreen(carContext)
        activeScreen = screen
        return screen
    }
}
