package com.smokebridge.smoke_bridge

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var binder: NetworkBinder? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "smokebridge/network_binder",
        )
        val b = NetworkBinder(applicationContext, channel)
        binder = b
        channel.setMethodCallHandler(b::onMethodCall)
    }

    override fun onDestroy() {
        // The guaranteed-release path: whatever Dart did or didn't do,
        // the process never outlives an activity holding a binding.
        binder?.unbind()
        binder = null
        super.onDestroy()
    }
}
