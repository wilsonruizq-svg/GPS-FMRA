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
  /// Estilo libre sin API key (calles OSM). Smoke alternativo: demotiles MapLibre.
  static const defaultMapStyleUrl =
      'https://tiles.openfreemap.org/styles/liberty';

  /// Demotiles MapLibre — siempre disponible, sin cuenta ni clave.
  static const demotilesStyleUrl =
      'https://demotiles.maplibre.org/style.json';

  static String get supabaseUrl => _read('SUPABASE_URL');

  static String get supabaseAnonKey => _read('SUPABASE_ANON_KEY');

  /// Opcional. Solo si se reactiva Google Maps (pausado por billing).
  static String get googleMapsApiKey => _read('GOOGLE_MAPS_API_KEY');

  /// Opcional. MapTiler Free: https://cloud.maptiler.com/ → API keys.
  static String get mapTilerApiKey => _read('MAPTILER_API_KEY');

  /// URL de estilo MapLibre. Si está vacía, se resuelve [mapStyleUrl].
  static String get mapStyleUrlOverride => _read('MAP_STYLE_URL');

  static bool get hasSupabaseConfig =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  /// True si hay una clave Google Maps real (ruta pausada; el mapa usa MapLibre).
  static bool get hasGoogleMapsConfig {
    final key = googleMapsApiKey.trim();
    if (key.isEmpty) return false;
    if (key.contains('your_google_maps') || key.contains('YOUR_')) {
      return false;
    }
    return true;
  }

  /// @Deprecated Use [hasGoogleMapsConfig]. Conservado por compatibilidad.
  static bool get hasMapsConfig => hasGoogleMapsConfig;

  static bool get hasMapTilerKey {
    final key = mapTilerApiKey.trim();
    if (key.isEmpty) return false;
    if (key.contains('your_maptiler') ||
        key.contains('YOUR_') ||
        key.contains('your_')) {
      return false;
    }
    return true;
  }

  /// Estilo efectivo para `MapLibreMap.styleString` (siempre hay uno usable sin pago).
  ///
  /// Orden: `MAP_STYLE_URL` → estilo MapTiler Streets con `MAPTILER_API_KEY` →
  /// OpenFreeMap Liberty (default, sin clave).
  static String get mapStyleUrl {
    final override = mapStyleUrlOverride.trim();
    if (override.isNotEmpty &&
        !override.contains('YOUR_') &&
        !override.contains('your_')) {
      return override;
    }
    if (hasMapTilerKey) {
      return 'https://api.maptiler.com/maps/streets-v2/style.json?key=$mapTilerApiKey';
    }
    return defaultMapStyleUrl;
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
      case 'MAPTILER_API_KEY':
        return const String.fromEnvironment(
          'MAPTILER_API_KEY',
          defaultValue: '',
        );
      case 'MAP_STYLE_URL':
        return const String.fromEnvironment(
          'MAP_STYLE_URL',
          defaultValue: '',
        );
      default:
        return '';
    }
  }
}
