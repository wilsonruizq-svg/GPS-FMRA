package com.gpsfmra.gps_fmra

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * GF-38: al encender el teléfono reinicia el keep-alive (FGS) y abre la app
 * para reanudar publicación si hay sesión/permisos. Sin bypass de GPS OFF.
 */
class BootReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent?) {
    val action = intent?.action ?: return
    if (action != Intent.ACTION_BOOT_COMPLETED &&
      action != Intent.ACTION_LOCKED_BOOT_COMPLETED &&
      action != Intent.ACTION_MY_PACKAGE_REPLACED
    ) {
      return
    }
    KeepAliveService.start(context.applicationContext, launchApp = true)
  }
}
