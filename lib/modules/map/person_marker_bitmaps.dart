import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Figuritas mujer/hombre coloreadas para pines MapLibre (`addImage`).
/// Dibujo vectorial (sin depender de glifos Material Icons).
class PersonMarkerBitmaps {
  PersonMarkerBitmaps._();

  static final Map<String, Uint8List> _cache = {};

  static String imageName({
    required bool female,
    required String colorHex,
  }) {
    final g = female ? 'f' : 'm';
    final hex = colorHex.replaceAll('#', '').toUpperCase();
    return 'person_${g}_$hex';
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
    final key = '${female ? 'f' : 'm'}_${argb.toRadixString(16)}_${logicalSize.round()}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final dpr = 2.0;
    final size = logicalSize * dpr;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final cx = size / 2;

    // Halo blanco.
    canvas.drawCircle(
      Offset(cx, size / 2),
      size * 0.46,
      Paint()
        ..color = const Color(0xF2FFFFFF)
        ..style = PaintingStyle.fill,
    );

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    // Cabeza
    final headR = size * 0.12;
    final headY = size * 0.28;
    canvas.drawCircle(Offset(cx, headY), headR, paint);

    if (female) {
      // Vestido (triángulo)
      final path = Path()
        ..moveTo(cx, headY + headR * 0.9)
        ..lineTo(cx - size * 0.22, size * 0.72)
        ..lineTo(cx + size * 0.22, size * 0.72)
        ..close();
      canvas.drawPath(path, paint);
      // Piernas
      final leg = Paint()
        ..color = color
        ..strokeWidth = size * 0.05
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(
        Offset(cx - size * 0.07, size * 0.72),
        Offset(cx - size * 0.07, size * 0.86),
        leg,
      );
      canvas.drawLine(
        Offset(cx + size * 0.07, size * 0.72),
        Offset(cx + size * 0.07, size * 0.86),
        leg,
      );
    } else {
      // Torso
      final bodyTop = headY + headR * 0.85;
      final bodyBottom = size * 0.62;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(cx - size * 0.1, bodyTop, cx + size * 0.1, bodyBottom),
          Radius.circular(size * 0.03),
        ),
        paint,
      );
      final stroke = Paint()
        ..color = color
        ..strokeWidth = size * 0.055
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      // Brazos
      canvas.drawLine(
        Offset(cx - size * 0.1, bodyTop + size * 0.08),
        Offset(cx - size * 0.22, bodyTop + size * 0.2),
        stroke,
      );
      canvas.drawLine(
        Offset(cx + size * 0.1, bodyTop + size * 0.08),
        Offset(cx + size * 0.22, bodyTop + size * 0.2),
        stroke,
      );
      // Piernas
      canvas.drawLine(
        Offset(cx - size * 0.05, bodyBottom),
        Offset(cx - size * 0.08, size * 0.86),
        stroke,
      );
      canvas.drawLine(
        Offset(cx + size * 0.05, bodyBottom),
        Offset(cx + size * 0.08, size * 0.86),
        stroke,
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.round(), size.round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) {
      throw StateError('No se pudo generar figurita PNG.');
    }
    final out = bytes.buffer.asUint8List();
    _cache[key] = out;
    return out;
  }
}

/// Resuelve mujer/hombre desde perfil o nombre (ES).
class PersonMarkerGender {
  PersonMarkerGender._();

  /// `true` = figurita mujer; `false` = hombre.
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
      'pilar', 'ines', 'inés', 'jimena', 'ximena', 'manuela', 'juliana',
      'lorena', 'vanessa', 'jessica', 'karen', 'nancy', 'elizabeth', 'luz',
    };
    if (femaleExact.contains(first)) return true;

    const maleExact = {
      'jose', 'josé', 'juan', 'carlos', 'luis', 'pedro', 'miguel', 'jorge',
      'francisco', 'antonio', 'manuel', 'diego', 'andres', 'andrés', 'felipe',
      'alejandro', 'sebastian', 'sebastián', 'daniel', 'david', 'ricardo',
      'rafael', 'oscar', 'óscar', 'hector', 'héctor', 'ivan', 'iván', 'pablo',
      'sergio', 'martin', 'martín', 'eduardo', 'fernando', 'alberto', 'raul',
      'raúl', 'roberto', 'julio', 'cesar', 'césar', 'gustavo', 'hugo',
      'wilson', 'william', 'edgar', 'edwin', 'nelson', 'german', 'germán',
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
