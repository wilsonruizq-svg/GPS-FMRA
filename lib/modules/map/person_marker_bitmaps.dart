import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Figuritas Material woman/man (estilo anterior). Sin círculo blanco.
class PersonMarkerBitmaps {
  PersonMarkerBitmaps._();

  static final Map<String, Uint8List> _cache = {};

  /// Lienzo 192 px. Antes ~0.57–0.63 (grandes); ~6 mm ≈ 0.34.
  static const imagePx = 192;
  static const mapIconSizeCompensated = 0.34;

  static String imageName({
    required bool female,
    required String colorHex,
  }) {
    final g = female ? 'f' : 'm';
    final hex = colorHex.replaceAll('#', '').toUpperCase();
    return 'person_v6_${g}_$hex';
  }

  static Future<Uint8List> png({
    required bool female,
    required Color color,
  }) async {
    final argb =
        ((color.a * 255).round() << 24) |
        ((color.r * 255).round() << 16) |
        ((color.g * 255).round() << 8) |
        (color.b * 255).round();
    final key = 'v6_${female ? 'f' : 'm'}_${argb.toRadixString(16)}';
    final cached = _cache[key];
    if (cached != null) return cached;

    const double size = imagePx * 1.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Lienzo transparente — sin círculo blanco.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size, size),
      Paint()..color = const Color(0x00000000),
    );

    final icon = female ? Icons.woman : Icons.man;
    final painter = TextPainter(textDirection: TextDirection.ltr);
    painter.text = TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: size * 0.78,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
        height: 1,
      ),
    );
    painter.layout();
    painter.paint(
      canvas,
      Offset(
        (size - painter.width) / 2,
        (size - painter.height) / 2 - size * 0.02,
      ),
    );

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
