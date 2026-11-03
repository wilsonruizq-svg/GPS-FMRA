import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'app.dart';
import 'core/supabase/supabase_bootstrap.dart';
import 'modules/push/push_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    try {
      await dotenv.load(fileName: '.env.example');
    } catch (_) {
      // Sin assets .env: usar --dart-define=SUPABASE_URL / SUPABASE_ANON_KEY.
    }
  }

  final supabaseReady = await bootstrapSupabase();

  // FCM opcional: sin google-services.json no bloquea el arranque.
  final push = PushService();
  await push.ensureInitialized();

  runApp(GpsFmraApp(supabaseReady: supabaseReady));
}
