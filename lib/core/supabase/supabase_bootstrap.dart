import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';

/// Inicializa Supabase si hay URL + anon/publishable key. Devuelve false si faltan.
Future<bool> bootstrapSupabase() async {
  if (!Env.hasSupabaseConfig) {
    debugPrint(
      'GPS-FMRA: faltan SUPABASE_URL / SUPABASE_ANON_KEY (.env o dart-define).',
    );
    return false;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabaseAnonKey,
  );
  return true;
}

SupabaseClient get supabase => Supabase.instance.client;
