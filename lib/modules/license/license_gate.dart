import 'package:flutter/material.dart';

import '../../app_shell.dart';
import 'license_service.dart';
import 'screens/license_blocked_screen.dart';

/// Tras login/sesión: AppShell solo si la licencia lo permite (GF-72).
Future<Widget> resolvePostAuthHome({
  bool supabaseReady = true,
  LicenseService? licenseService,
}) async {
  final access = await (licenseService ?? LicenseService()).ensureAccess();
  if (access.allowed) {
    return const AppShell();
  }
  return LicenseBlockedScreen(
    access: access,
    supabaseReady: supabaseReady,
  );
}
