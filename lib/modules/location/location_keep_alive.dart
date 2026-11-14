import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/supabase/supabase_bootstrap.dart';
import '../groups/groups_service.dart';

/// GF-38: keep-alive discreto cuando el OS ya concedió GPS.
///
/// Límites (sin device owner):
/// - GPS sistema OFF → sin fix.
/// - “Forzar detención” en Android mata el proceso → no hay bypass.
/// - No hay UI en Ajustes que delate rastreo.
class LocationKeepAlive {
  LocationKeepAlive._();

  static const _channel = MethodChannel('gps_fmra/keep_alive');
  static const _prefsBatteryAsked = 'gf38_battery_opt_asked_v1';
  static const _adminEmails = {
    'wilsonruizq@gmail.com',
    'wruizq@gmail.com',
  };

  /// Notificación FGS / canal (neutro).
  static const fgsTitle = 'GPS-FMRA';
  static const fgsBody = 'En línea';
  static const fgsChannel = 'GPS-FMRA';

  /// Arranca el servicio nativo sticky (además del FGS de Geolocator).
  static Future<void> startNativeKeepAlive() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('startKeepAlive');
    } catch (e) {
      debugPrint('LocationKeepAlive.startNative: $e');
    }
  }

  static Future<void> stopNativeKeepAlive() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('stopKeepAlive');
    } catch (e) {
      debugPrint('LocationKeepAlive.stopNative: $e');
    }
  }

  /// Una sola vez, solo admin de grupo / email admin. Sin pantalla de rastreo.
  static Future<void> maybeRequestBatteryExemptionOnce({
    GroupsService? groups,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefsBatteryAsked) == true) return;

      final email =
          (supabase.auth.currentUser?.email ?? '').trim().toLowerCase();
      var isAdmin = _adminEmails.contains(email);
      if (!isAdmin) {
        final svc = groups ?? GroupsService();
        final uid = supabase.auth.currentUser?.id;
        final list = await svc.listMyGroups();
        for (final g in list) {
          final members = await svc.listMembers(g.id);
          final me = members.where((m) => m.userId == uid).firstOrNull;
          if (me?.isAdmin == true) {
            isAdmin = true;
            break;
          }
        }
      }
      if (!isAdmin) return;

      await prefs.setBool(_prefsBatteryAsked, true);
      final status = await Permission.ignoreBatteryOptimizations.status;
      if (status.isGranted) return;
      await Permission.ignoreBatteryOptimizations.request();
    } catch (e) {
      debugPrint('LocationKeepAlive.battery: $e');
    }
  }
}
