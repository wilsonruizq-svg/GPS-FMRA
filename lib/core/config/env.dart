/// Lectura de configuración vía --dart-define (sin secretos en el repo).
///
/// Ejemplo:
/// ```
/// flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=eyJ... \
///   --dart-define=GOOGLE_MAPS_API_KEY=AIza...
/// ```
abstract final class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );

  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  static const googleMapsApiKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
    defaultValue: '',
  );

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static bool get hasMapsConfig => googleMapsApiKey.isNotEmpty;
}
