import 'package:flutter/material.dart';

import 'core/l10n/app_strings.dart';
import 'core/theme/app_theme.dart';
import 'modules/auth/screens/splash_screen.dart';

class GpsFmraApp extends StatelessWidget {
  const GpsFmraApp({super.key, this.supabaseReady = false});

  final bool supabaseReady;

  /// Para snackbars globales (p. ej. alerta de chat fuera de la pantalla).
  static final messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('es'),
      scaffoldMessengerKey: messengerKey,
      home: SplashScreen(supabaseReady: supabaseReady),
    );
  }
}
