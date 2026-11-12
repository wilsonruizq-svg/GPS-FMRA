import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Silueta tipo señalética (cabeza redonda + cuerpo único). Sin círculo de fondo.
/// Referencia: media/map-person-silhouette.png
class PersonMarkerBitmaps {
  PersonMarkerBitmaps._();

  static final Map<String, Uint8List> _cache = {};

  static String imageName({
    required bool female,
    required String colorHex,
  }) {
    final g = female ? 'f' : 'm';
    final hex = colorHex.replaceAll('#', '').toUpperCase();
    return 'person_v4_${g}_$hex';
  }

  static Future<Uint8List> png({
    required bool female,
    required Color color,
    double logicalSize = 96,
  }) async {
    final argb =
        ((color.a * 255).round() << 24) |
        ((color.r * 255).round() << 16) |
        ((color.g * 255).round() << 8) |
        (color.b * 255).round();
    final key =
        'v4_${female ? 'f' : 'm'}_${argb.toRadixString(16)}_${logicalSize.round()}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final dpr = 2.0;
    final size = logicalSize * dpr;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final cx = size / 2;
    // Proporciones tipo pictograma: cabeza separada + torso cónico.
    final headR = size * (female ? 0.145 : 0.15);
    final headCy = size * 0.22;
    final gap = size * 0.035;
    final bodyTop = headCy + headR + gap;
    final bodyBottom = size * 0.92;
    // Hombros redondeados; mujer un poco más estrecha arriba / base similar.
    final shoulderW = size * (female ? 0.52 : 0.56);
    final baseW = size * (female ? 0.22 : 0.20);

    // Cabeza (círculo separado).
    canvas.drawCircle(Offset(cx, headCy), headR, paint);

    // Cuerpo: un solo bloque con hombros redondeados y base plana.
    final body = Path()
      ..moveTo(cx - shoulderW / 2, bodyTop + size * 0.08)
      ..quadraticBezierTo(
        cx - shoulderW / 2,
        bodyTop,
        cx - shoulderW / 2 + size * 0.08,
        bodyTop,
      )
      ..lineTo(cx + shoulderW / 2 - size * 0.08, bodyTop)
      ..quadraticBezierTo(
        cx + shoulderW / 2,
        bodyTop,
        cx + shoulderW / 2,
        bodyTop + size * 0.08,
      )
      ..lineTo(cx + baseW / 2, bodyBottom)
      ..lineTo(cx - baseW / 2, bodyBottom)
      ..close();
    canvas.drawPath(body, paint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.round(), size.round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) {
      throw StateError('No se pudo generar silueta PNG.');
    }
    final out = bytes.buffer.asUint8List();
    _cache[key] = out;
    return out;
  }
}

/// Resuelve mujer/hombre desde perfil o nombre (ES).
class PersonMarkerGender {
  PersonMarkerGender._();

  static bool isFemale({
    String? gender,
    String? displayName,
  }) {
    final g = gender?.trim().toLowerCase();
    if (g == 'female' || g == 'mujer' || g == 'f' || g == 'femenino') {
      return true;
    }
    if (g == 'male' || g == 'hombre' || g == 'm' || g == 'masculino') {
      return false;
    }
    return _inferFemaleFromName(displayName);
  }

  static bool _inferFemaleFromName(String? raw) {
    final name = (raw ?? '').trim().toLowerCase();
    if (name.isEmpty) return false;
    final first = name.split(RegExp(r'\s+')).first;

    const femaleExact = {
      'maria', 'maría', 'ana', 'lucia', 'lucía', 'sofia', 'sofía', 'laura',
      'carmen', 'isabel', 'andrea', 'patricia', 'claudia', 'diana', 'elena',
      'gabriela', 'valentina', 'camila', 'daniela', 'paola', 'alejandra',
      'carolina', 'fernanda', 'monica', 'mónica', 'rosa', 'juana', 'adriana',
      'beatriz', 'catalina', 'veronica', 'verónica', 'natalia', 'sandra',
      'liliana', 'martha', 'marta', 'gloria', 'angela', 'ángela', 'teresa',
      'jimena', 'ximena', 'manuela', 'juliana', 'lorena', 'vanessa', 'luz',
    };
    if (femaleExact.contains(first)) return true;

    const maleExact = {
      'jose', 'josé', 'juan', 'carlos', 'luis', 'pedro', 'miguel', 'jorge',
      'francisco', 'antonio', 'manuel', 'diego', 'andres', 'andrés', 'felipe',
      'alejandro', 'sebastian', 'sebastián', 'daniel', 'david', 'ricardo',
      'rafael', 'oscar', 'óscar', 'hector', 'héctor', 'ivan', 'iván', 'pablo',
      'sergio', 'martin', 'martín', 'eduardo', 'fernando', 'alberto', 'raul',
      'raúl', 'roberto', 'julio', 'cesar', 'césar', 'wilson', 'william',
      'orlando', 'mauricio', 'javier', 'santiago', 'mateo', 'cristian',
    };
    if (maleExact.contains(first)) return false;

    if (first.endsWith('a') &&
        !const {'joshua', 'elias', 'elías', 'matias', 'matías', 'jonas', 'jonás'}
            .contains(first)) {
      return true;
    }
    return false;
  }
}
