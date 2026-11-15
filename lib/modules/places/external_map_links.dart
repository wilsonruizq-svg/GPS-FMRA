import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// URLs y apertura en mapas externos (Google Earth/Maps, OSM, geo:) —
/// solo por acción explícita del usuario.
class ExternalMapLinks {
  ExternalMapLinks._();

  static const _defaultOsmZoom = 17;

  static String googleEarthWebUrl({
    required double lat,
    required double lng,
  }) =>
      'https://earth.google.com/web/@$lat,$lng,120a,50000d,35y,0h,0t,0r';

  static String googleMapsSearchUrl({
    required double lat,
    required double lng,
  }) =>
      'https://www.google.com/maps/search/?api=1&query=$lat,$lng';

  static String openStreetMapWebUrl({
    required double lat,
    required double lng,
    int zoom = _defaultOsmZoom,
  }) =>
      'https://www.openstreetmap.org/?mlat=$lat&mlon=$lng#map=$zoom/$lat/$lng';

  /// RFC 5870 — `ACTION_VIEW`; Android ofrece Organic Maps, OsmAnd, etc.
  static String geoUri({
    required double lat,
    required double lng,
    String? label,
  }) {
    final coords = '$lat,$lng';
    var q = coords;
    final l = label?.trim();
    if (l != null && l.isNotEmpty) {
      q = '$coords(${Uri.encodeComponent(l)})';
    }
    return 'geo:$coords?q=$q';
  }

  /// Fallback si `geo:` no resuelve (p. ej. sin manejador visible).
  static String organicMapsOmUrl({
    required double lat,
    required double lng,
    String? label,
  }) {
    final base = 'om://map?v=1&ll=$lat,$lng';
    final l = label?.trim();
    if (l != null && l.isNotEmpty) {
      return '$base&n=${Uri.encodeComponent(l)}';
    }
    return base;
  }

  static Future<bool> launchUrlString(String url) async {
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && kDebugMode) {
        debugPrint('ExternalMapLinks: launchUrl returned false for $url');
      }
      return launched;
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('ExternalMapLinks.launchUrlString: $e\n$st');
      }
      return false;
    }
  }

  static Future<bool> openGoogleEarth({
    required double lat,
    required double lng,
  }) =>
      launchUrlString(googleEarthWebUrl(lat: lat, lng: lng));

  static Future<bool> openGoogleMaps({
    required double lat,
    required double lng,
  }) =>
      launchUrlString(googleMapsSearchUrl(lat: lat, lng: lng));

  static Future<bool> openOpenStreetMap({
    required double lat,
    required double lng,
  }) =>
      launchUrlString(openStreetMapWebUrl(lat: lat, lng: lng));

  static Future<bool> openGeoAppPicker({
    required double lat,
    required double lng,
    String? label,
  }) =>
      launchUrlString(geoUri(lat: lat, lng: lng, label: label));

  /// Preferir `geo:` (selector → Organic Maps); si falla, esquema `om://`.
  static Future<bool> openPreferredMapApp({
    required double lat,
    required double lng,
    String? label,
  }) async {
    if (await openGeoAppPicker(lat: lat, lng: lng, label: label)) {
      return true;
    }
    return launchUrlString(
      organicMapsOmUrl(lat: lat, lng: lng, label: label),
    );
  }
}