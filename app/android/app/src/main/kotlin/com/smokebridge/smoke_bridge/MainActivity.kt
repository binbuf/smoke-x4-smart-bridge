package com.smokebridge.smoke_bridge

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var binder: NetworkBinder? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // N15.19 — the AP-routing binder.
        val channel = MethodChannel(messenger, "smokebridge/network_binder")
        val b = NetworkBinder(applicationContext, channel)
        binder = b
        channel.setMethodCallHandler(b::onMethodCall)

        // N15.18 — the OS-settings deep-links the preflight gate needs (13
        // §13.2.0), on a SEPARATE channel so it never disturbs the binder.
        MethodChannel(messenger, "smokebridge/system_settings")
            .setMethodCallHandler(::onSettingsCall)
    }

    /**
     * N15.18 — each preflight "Open … settings" button is a system Intent with
     * no plugin equivalent. `androidSdkInt` lets the Dart permission/location
     * gates decide which legacy legs apply (05 §5.8.3). A missing settings
     * screen answers `error` rather than crashing; the Dart wrapper swallows it.
     */
    private fun onSettingsCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "androidSdkInt" -> result.success(Build.VERSION.SDK_INT)
            "openBluetoothSettings" ->
                openSettings(Intent(Settings.ACTION_BLUETOOTH_SETTINGS), result)
            "openWifiSettings" ->
                openSettings(Intent(Settings.ACTION_WIFI_SETTINGS), result)
            "openLocationSettings" ->
                openSettings(Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS), result)
            "openNotificationSettings" ->
                openSettings(notificationSettingsIntent(), result)
            "openAppSettings" ->
                openSettings(appDetailsIntent(), result)
            else -> result.notImplemented()
        }
    }

    private fun openSettings(intent: Intent, result: MethodChannel.Result) {
        // Started from the Activity, but flag NEW_TASK so the settings screen is
        // its own task and Back returns cleanly to setup.
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try {
            startActivity(intent)
            result.success(null)
        } catch (e: ActivityNotFoundException) {
            result.error("no_activity", "no settings screen for ${intent.action}", null)
        }
    }

    private fun appDetailsIntent() = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.fromParts("package", packageName, null),
    )

    private fun notificationSettingsIntent(): Intent =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            // Pre-O has no per-app notification screen; the app page is the
            // honest fallback.
            appDetailsIntent()
        }

    override fun onDestroy() {
        // The guaranteed-release path: whatever Dart did or didn't do,
        // the process never outlives an activity holding a binding.
        binder?.unbind()
        binder = null
        super.onDestroy()
    }
}
