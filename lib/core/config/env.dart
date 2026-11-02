import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Configuración local vía `.env` (flutter_dotenv) con fallback a `--dart-define`.
///
/// ```
/// flutter run
/// # o:
/// flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJ...
/// ```
///
/// `SUPABASE_ANON_KEY` acepta `sb_publishable_...` (recomendado en SDKs recientes)
/// o el JWT legacy `anon`/`public` (`eyJ...`) de Project Settings → API.
abstract final class Env {
  static String get supabaseUrl => _read('SUPABASE_URL');

  static String get supabaseAnonKey => _read('SUPABASE_ANON_KEY');

  static String get googleMapsApiKey => _read('GOOGLE_MAPS_API_KEY');

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasMapsConfig {
    final key = googleMapsApiKey.trim();
    if (key.isEmpty) return false;
    if (key.contains('your_google_maps') || key.contains('YOUR_')) {
      return false;
    }
    return true;
  }

  /// True si la clave no parece un JWT anon clásico (`eyJ...`).
  static bool get anonKeyLooksNonJwt {
    final key = supabaseAnonKey.trim();
    return key.isNotEmpty && !key.startsWith('eyJ');
  }

  static String _read(String name) {
    final fromDotenv = dotenv.isInitialized
        ? (dotenv.env[name] ?? '').trim()
        : '';
    if (fromDotenv.isNotEmpty) return fromDotenv;

    switch (name) {
      case 'SUPABASE_URL':
        return const String.fromEnvironment('SUPABASE_URL', defaultValue: '');
      case 'SUPABASE_ANON_KEY':
        return const String.fromEnvironment(
          'SUPABASE_ANON_KEY',
          defaultValue: '',
        );
      case 'GOOGLE_MAPS_API_KEY':
        return const String.fromEnvironment(
          'GOOGLE_MAPS_API_KEY',
          defaultValue: '',
        );
      default:
        return '';
    }
  }
}
