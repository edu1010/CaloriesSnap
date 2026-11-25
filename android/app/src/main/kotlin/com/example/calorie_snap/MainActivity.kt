package com.example.calorie_snap

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

// A FragmentActivity because Health Connect's permission request needs the
// AndroidX activity-result API, which the plain FlutterActivity lacks.
class MainActivity : FlutterFragmentActivity() {
    private val healthConnect = HealthConnectChannel(this)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        healthConnect.attach(flutterEngine.dartExecutor.binaryMessenger)
    }
}
