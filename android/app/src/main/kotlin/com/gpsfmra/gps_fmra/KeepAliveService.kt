package com.gpsfmra.gps_fmra

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat

/**
 * GF-38: servicio en primer plano discreto para mantener el proceso vivo.
 * Texto neutro (sin “rastreo” / GPS). No bypass del interruptor GPS del sistema.
 */
class KeepAliveService : Service() {
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    ensureChannel()
    val notification = buildNotification()
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
      ServiceCompat.startForeground(
        this,
        NOTIFICATION_ID,
        notification,
        ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
      )
    } else {
      startForeground(NOTIFICATION_ID, notification)
    }

    // Tras BOOT / reinicio: abrir la app para que Dart reanude el stream GPS.
    if (intent?.getBooleanExtra(EXTRA_LAUNCH_APP, false) == true) {
      val launch = Intent(this, MainActivity::class.java).apply {
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        putExtra(EXTRA_FROM_KEEPALIVE, true)
      }
      try {
        startActivity(launch)
      } catch (_: Exception) {
        // Android puede bloquear activity desde background; el FGS sigue.
      }
    }
    return START_STICKY
  }

  private fun ensureChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val mgr = getSystemService(NotificationManager::class.java) ?: return
    val channel = NotificationChannel(
      CHANNEL_ID,
      CHANNEL_NAME,
      NotificationManager.IMPORTANCE_LOW,
    ).apply {
      description = CHANNEL_NAME
      setShowBadge(false)
    }
    mgr.createNotificationChannel(channel)
  }

  private fun buildNotification(): Notification {
    val open = Intent(this, MainActivity::class.java).apply {
      addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
    }
    val pending = PendingIntent.getActivity(
      this,
      0,
      open,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
    return NotificationCompat.Builder(this, CHANNEL_ID)
      .setContentTitle(TITLE)
      .setContentText(BODY)
      .setSmallIcon(R.mipmap.ic_launcher)
      .setOngoing(true)
      .setSilent(true)
      .setContentIntent(pending)
      .setCategory(NotificationCompat.CATEGORY_SERVICE)
      .setPriority(NotificationCompat.PRIORITY_LOW)
      .build()
  }

  companion object {
    const val CHANNEL_ID = "gps_fmra_keepalive"
    const val CHANNEL_NAME = "GPS-FMRA"
    const val TITLE = "GPS-FMRA"
    const val BODY = "En línea"
    const val NOTIFICATION_ID = 3801
    const val EXTRA_LAUNCH_APP = "launch_app"
    const val EXTRA_FROM_KEEPALIVE = "from_keepalive"

    fun start(context: Context, launchApp: Boolean = false) {
      val intent = Intent(context, KeepAliveService::class.java).apply {
        putExtra(EXTRA_LAUNCH_APP, launchApp)
      }
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        context.startForegroundService(intent)
      } else {
        context.startService(intent)
      }
    }

    fun stop(context: Context) {
      context.stopService(Intent(context, KeepAliveService::class.java))
    }
  }
}
