package com.smokebridge.smoke_bridge

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * A14.2 — the Kotlin half of the AP-routing mitigation (design 05
 * §5.8.1–5.8.2). Ours, not a package: the failure mode of forgetting to
 * unbind is "the app has no internet anywhere, forever", so lifecycle
 * control must be exact. Unbind runs on explicit call, on onLost, and on
 * activity destroy — every path.
 *
 * The request asks for TRANSPORT_WIFI with NET_CAPABILITY_INTERNET
 * REMOVED — that is the whole trick. Android will happily hand over an
 * internet-less Wi-Fi network when the app says it does not need
 * internet from it; bindProcessToNetwork then routes this process's
 * sockets there while the rest of the phone keeps cellular.
 */
class NetworkBinder(private val context: Context, private val channel: MethodChannel) {

    private val connectivity =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val mainHandler = Handler(Looper.getMainLooper())
    private var callback: ConnectivityManager.NetworkCallback? = null

    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "bind" -> bind(null, null, result)
            "joinAp" -> bind(call.argument("ssid"), call.argument("psk"), result)
            "unbind" -> {
                unbind()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun bind(ssid: String?, psk: String?, result: MethodChannel.Result) {
        if (callback != null) {
            // The Dart side gates this; a second request reaching here is
            // a defect, answered deterministically rather than platform luck.
            result.error("already_bound", "bind while bound", null)
            return
        }
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .apply {
                if (ssid != null && psk != null &&
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                ) {
                    // The one-tap join: credentials from provisioning, no
                    // Settings round-trip (§5.8.2).
                    setNetworkSpecifier(
                        WifiNetworkSpecifier.Builder()
                            .setSsid(ssid)
                            .setWpa2Passphrase(psk)
                            .build()
                    )
                }
            }
            .build()

        var answered = false
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                connectivity.bindProcessToNetwork(network)
                mainHandler.post {
                    if (!answered) {
                        answered = true
                        result.success(null)
                    }
                    channel.invokeMethod("onBound", null)
                }
            }

            override fun onLost(network: Network) {
                // Release FIRST, then report: the app must never sit on a
                // binding to a network that no longer exists.
                connectivity.bindProcessToNetwork(null)
                mainHandler.post { channel.invokeMethod("onLost", null) }
                clear()
            }

            override fun onUnavailable() {
                connectivity.bindProcessToNetwork(null)
                mainHandler.post {
                    if (!answered) {
                        answered = true
                        result.error("unavailable", "network unavailable", null)
                    }
                }
                clear()
            }
        }
        callback = cb
        connectivity.requestNetwork(request, cb)
    }

    fun unbind() {
        connectivity.bindProcessToNetwork(null)
        clear()
    }

    private fun clear() {
        callback?.let {
            try {
                connectivity.unregisterNetworkCallback(it)
            } catch (_: IllegalArgumentException) {
                // Already unregistered (onLost raced an explicit unbind).
            }
        }
        callback = null
    }
}
