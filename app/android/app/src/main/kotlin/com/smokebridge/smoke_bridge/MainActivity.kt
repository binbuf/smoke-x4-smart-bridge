package com.smokebridge.smoke_bridge

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The thin Android half of the app's platform seam (`smokebridge/platform`).
 *
 * It does exactly two things the Dart side cannot: ask for runtime Bluetooth
 * permissions, and open the two OS settings screens a blocked connection needs
 * (the radio is off, or a permission was permanently refused). The *decision*
 * of which permissions an OS version needs lives in Dart
 * (`androidBlePermissions`) so there is one source of truth; this side only maps
 * the names it is handed to `Manifest.permission` constants.
 */
class MainActivity : FlutterActivity() {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingPermissions: Array<String> = emptyArray()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "smokebridge/platform")
        channel.setMethodCallHandler(::onPlatformCall)
    }

    private fun onPlatformCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "androidSdkInt" -> result.success(Build.VERSION.SDK_INT)
            "requestPermissions" -> requestBlePermissions(call, result)
            "openBluetoothSettings" ->
                openSettings(Intent(Settings.ACTION_BLUETOOTH_SETTINGS), result)
            "openAppSettings" -> openSettings(appDetailsIntent(), result)
            else -> result.notImplemented()
        }
    }

    private fun requestBlePermissions(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            // No runtime permissions before Android 6.
            result.success(statusMap(true, false))
            return
        }
        val names = call.argument<List<String>>("permissions").orEmpty()
        val perms = names.mapNotNull(::manifestPermission).toTypedArray()
        if (perms.isEmpty()) {
            result.success(statusMap(true, false))
            return
        }
        if (perms.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }) {
            result.success(statusMap(true, false))
            return
        }
        // One request in flight at a time; the app only ever asks during connect.
        pendingResult = result
        pendingPermissions = perms
        requestPermissions(perms, REQUEST_BLE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_BLE) return
        val granted = grantResults.isNotEmpty() &&
            grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        // "Don't ask again" reads as denied with no rationale to show; that is
        // the one case only the app's settings page can fix.
        val permanentlyDenied = !granted && pendingPermissions.any { perm ->
            grantResults.getOrNull(pendingPermissions.indexOf(perm)) !=
                PackageManager.PERMISSION_GRANTED &&
                !shouldShowRequestPermissionRationale(perm)
        }
        pendingResult?.success(statusMap(granted, permanentlyDenied))
        pendingResult = null
        pendingPermissions = emptyArray()
    }

    private fun statusMap(granted: Boolean, permanentlyDenied: Boolean) = mapOf(
        "granted" to granted,
        "permanentlyDenied" to permanentlyDenied,
        "sdkInt" to Build.VERSION.SDK_INT,
    )

    private fun manifestPermission(name: String): String? = when (name) {
        "BLUETOOTH_SCAN" -> Manifest.permission.BLUETOOTH_SCAN
        "BLUETOOTH_CONNECT" -> Manifest.permission.BLUETOOTH_CONNECT
        "ACCESS_FINE_LOCATION" -> Manifest.permission.ACCESS_FINE_LOCATION
        "ACCESS_COARSE_LOCATION" -> Manifest.permission.ACCESS_COARSE_LOCATION
        else -> null
    }

    private fun openSettings(intent: Intent, result: MethodChannel.Result) {
        // Started from the Activity, but flag NEW_TASK so the settings screen is
        // its own task and Back returns cleanly to the app.
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

    companion object {
        private const val REQUEST_BLE = 0x5B1E
    }
}