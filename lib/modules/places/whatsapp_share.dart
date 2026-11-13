import 'package:url_launcher/url_launcher.dart';

/// Comparte un lugar por WhatsApp (texto + enlace de mapas).
class WhatsAppShare {
  WhatsAppShare._();

  static String mapsUrl({required double lat, required double lon}) =>
      'https://maps.google.com/?q=$lat,$lon';

  static String message({
    required String name,
    required double lat,
    required double lon,
  }) {
    final n = name.trim().isEmpty ? 'Mi ubicación' : name.trim();
    return '$n\n${mapsUrl(lat: lat, lon: lon)}';
  }

  /// Abre WhatsApp con el texto listo (o el selector si no hay WhatsApp).
  static Future<bool> sharePlace({
    required String name,
    required double lat,
    required double lon,
  }) async {
    final text = message(name: name, lat: lat, lon: lon);
    final encoded = Uri.encodeComponent(text);

    final candidates = <Uri>[
      Uri.parse('whatsapp://send?text=$encoded'),
      Uri.parse('https://wa.me/?text=$encoded'),
    ];

    for (final uri in candidates) {
      try {
        if (await canLaunchUrl(uri)) {
          final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
          if (ok) return true;
        }
      } catch (_) {}
    }
    return false;
  }
}
