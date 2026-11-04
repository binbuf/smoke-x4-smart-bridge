package com.binbuf.smoke_bridge

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val DEVICE_INFO_CHANNEL = "smoke_bridge/device_info"
        private const val ALARM_CHANNEL = "smoke_bridge/alarm"
        private const val ALARM_NOTIFICATION_CHANNEL = "smoke_x_alarm"
        private const val ALARM_NOTIFICATION_CHANNEL_NAME = "Smoke X alarms"
        private const val ALARM_NOTIFICATION_CHANNEL_DESC =
            "Probe high and low alarm alerts from the Smoke X Bridge"
        private const val EXTRA_ALARM_PROBE_MASK = "alarm_probe_mask"
        private const val DEFAULT_ALARM_NOTIFICATION_ID = 4100
    }

    private var alarmChannel: MethodChannel? = null
    private var pendingAlarmMask = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingAlarmMask = intent?.getIntExtra(EXTRA_ALARM_PROBE_MASK, 0) ?: 0
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_INFO_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "get") {
                result.success(
                    mapOf(
                        "model" to Build.MODEL,
                        "manufacturer" to Build.MANUFACTURER,
                        "release" to Build.VERSION.RELEASE,
                        "sdkInt" to Build.VERSION.SDK_INT,
                    ),
                )
            } else {
                result.notImplemented()
            }
        }

        ensureAlarmChannel()
        alarmChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ALARM_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> {
                        requestNotificationPermissionIfNeeded()
                        val mask = pendingAlarmMask
                        pendingAlarmMask = 0
                        result.success(mask)
                    }
                    "showAlarm" -> {
                        val args = call.arguments as? Map<*, *>
                        showAlarmNotification(
                            id = (args?.get("id") as? Number)?.toInt()
                                ?: DEFAULT_ALARM_NOTIFICATION_ID,
                            title = args?.get("title") as? String ?: "Smoke X alarm",
                            body = args?.get("body") as? String ?: "",
                            probeMask = (args?.get("probeMask") as? Number)?.toInt() ?: 0,
                        )
                        result.success(null)
                    }
                    "cancelAlarm" -> {
                        val id = (call.arguments as? Map<*, *>)?.get("id") as? Number
                        cancelAlarmNotification(
                            id?.toInt() ?: DEFAULT_ALARM_NOTIFICATION_ID,
                        )
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val mask = intent.getIntExtra(EXTRA_ALARM_PROBE_MASK, 0)
        if (mask != 0) {
            deliverAlarmOpen(mask)
        }
    }

    private fun deliverAlarmOpen(mask: Int) {
        val channel = alarmChannel
        if (channel == null) {
            pendingAlarmMask = mask
        } else {
            channel.invokeMethod("alarmOpened", mask)
        }
    }

    private fun ensureAlarmChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            ALARM_NOTIFICATION_CHANNEL,
            ALARM_NOTIFICATION_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = ALARM_NOTIFICATION_CHANNEL_DESC
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            DEFAULT_ALARM_NOTIFICATION_ID,
        )
    }

    private fun showAlarmNotification(
        id: Int,
        title: String,
        body: String,
        probeMask: Int,
    ) {
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(EXTRA_ALARM_PROBE_MASK, probeMask)
        }
        val immutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE
        } else {
            0
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or immutable
        val contentIntent = PendingIntent.getActivity(this, probeMask, launchIntent, flags)
        val notification = NotificationCompat.Builder(this, ALARM_NOTIFICATION_CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_alarm)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .addAction(0, "Acknowledge", contentIntent)
            .build()
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(id, notification)
    }

    private fun cancelAlarmNotification(id: Int) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.cancel(id)
    }
}
