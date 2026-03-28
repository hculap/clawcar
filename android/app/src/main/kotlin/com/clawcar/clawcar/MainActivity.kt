package com.clawcar.clawcar

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.clawcar.clawcar.car.AndroidAutoBridge

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        AndroidAutoBridge.register(flutterEngine)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        AndroidAutoBridge.unregister()
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
