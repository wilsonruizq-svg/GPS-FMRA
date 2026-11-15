import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'external_map_links.dart';

/// Comparte un lugar (hoja de compartir de Android; WhatsApp si el usuario elige).
/// GF-64: texto = título/detalle opcional + enlace **solo** Google Maps (pin exacto).
class WhatsAppShare {
  WhatsAppShare._();

  static String mapsUrl({required double lat, required double lon}) =>
      ExternalMapLinks.googleMapsSearchUrl(lat: lat, lng: lon);

  static String message({
    required String name,
    required double lat,
    required double lon,
    String? detail,
  }) {
    final n = name.trim().isEmpty ? 'Mi ubicación' : name.trim();
    final lines = <String>[n];
    final d = detail?.trim();
    if (d != null && d.isNotEmpty) lines.add(d);
    lines.add(mapsUrl(lat: lat, lon: lon));
    return lines.join('\n');
  }

  /// Abre la hoja de compartir del sistema (texto + foto JPEG opcional).
  static Future<bool> sharePlace({
    required String name,
    required double lat,
    required double lon,
    String? detail,
    Uint8List? photoJpeg,
  }) async {
    final text = message(name: name, lat: lat, lon: lon, detail: detail);
    try {
      if (photoJpeg != null && photoJpeg.isNotEmpty) {
        final dir = await getTemporaryDirectory();
        final path =
            '${dir.path}/gps_fmra_place_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(path);
        await file.writeAsBytes(photoJpeg, flush: true);
        final box = await _shareOriginBox();
        final result = await Share.shareXFiles(
          [XFile(file.path, mimeType: 'image/jpeg', name: 'lugar.jpg')],
          text: text,
          subject: name.trim().isEmpty ? 'Ubicación' : name.trim(),
          sharePositionOrigin: box,
        );
        return _shareOk(result);
      }
      final box = await _shareOriginBox();
      final result = await Share.share(
        text,
        subject: name.trim().isEmpty ? 'Ubicación' : name.trim(),
        sharePositionOrigin: box,
      );
      return _shareOk(result);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('WhatsAppShare.sharePlace: $e\n$st');
      }
      return false;
    }
  }

  static bool _shareOk(ShareResult result) {
    return result.status == ShareResultStatus.success ||
        result.status == ShareResultStatus.dismissed;
  }

  static Future<Rect?> _shareOriginBox() async {
    // En móvil no hace falta; en tablet/web evita fallos de origin.
    return null;
  }
}