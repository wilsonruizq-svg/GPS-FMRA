import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Siluetas humanas (sin círculo de fondo) para pines MapLibre.
class PersonMarkerBitmaps {
  PersonMarkerBitmaps._();

  static final Map<String, Uint8List> _cache = {};

  static String imageName({
    required bool female,
    required String colorHex,
  }) {
    final g = female ? 'f' : 'm';
    final hex = colorHex.replaceAll('#', '').toUpperCase();
    return 'person_v3_${g}_$hex';
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
        'v3_${female ? 'f' : 'm'}_${argb.toRadixString(16)}_${logicalSize.round()}';
    final cached = _cache[key];
    if (cached != null) return cached;

    final dpr = 2.0;
    final size = logicalSize * dpr;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Lienzo transparente — solo silueta.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size, size),
      Paint()..color = const Color(0x00000000),
    );

    final cx = size / 2;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    final outline = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.035
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final path = female ? _femalePath(size, cx) : _malePath(size, cx);
    canvas.drawPath(path, outline);
    canvas.drawPath(path, fill);

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

  /// Hombre: cabeza + torso + brazos + piernas (proporciones naturales).
  static Path _malePath(double size, double cx) {
    final headR = size * 0.11;
    final headCy = size * 0.22;
    final shoulderY = headCy + headR + size * 0.02;
    final hipY = size * 0.58;
    final footY = size * 0.92;
    final shoulderW = size * 0.28;
    final hipW = size * 0.16;
    final armOut = size * 0.34;
    final armY = size * 0.48;

    final p = Path();
    // Cabeza
    p.addOval(Rect.fromCircle(center: Offset(cx, headCy), radius: headR));
    // Cuello + torso (trapecio suave)
    p.moveTo(cx - size * 0.05, shoulderY);
    p.lineTo(cx - shoulderW / 2, shoulderY + size * 0.04);
    p.lineTo(cx - hipW / 2, hipY);
    p.lineTo(cx + hipW / 2, hipY);
    p.lineTo(cx + shoulderW / 2, shoulderY + size * 0.04);
    p.lineTo(cx + size * 0.05, shoulderY);
    p.close();
    // Brazo izquierdo
    p.moveTo(cx - shoulderW / 2 + size * 0.02, shoulderY + size * 0.06);
    p.lineTo(cx - armOut, armY);
    p.lineTo(cx - armOut + size * 0.04, armY + size * 0.03);
    p.lineTo(cx - shoulderW / 2 + size * 0.06, shoulderY + size * 0.12);
    p.close();
    // Brazo derecho
    p.moveTo(cx + shoulderW / 2 - size * 0.02, shoulderY + size * 0.06);
    p.lineTo(cx + armOut, armY);
    p.lineTo(cx + armOut - size * 0.04, armY + size * 0.03);
    p.lineTo(cx + shoulderW / 2 - size * 0.06, shoulderY + size * 0.12);
    p.close();
    // Pierna izquierda
    p.moveTo(cx - hipW / 2, hipY);
    p.lineTo(cx - size * 0.12, footY);
    p.lineTo(cx - size * 0.04, footY);
    p.lineTo(cx - size * 0.02, hipY);
    p.close();
    // Pierna derecha
    p.moveTo(cx + hipW / 2, hipY);
    p.lineTo(cx + size * 0.12, footY);
    p.lineTo(cx + size * 0.04, footY);
    p.lineTo(cx + size * 0.02, hipY);
    p.close();
    return p;
  }

  /// Mujer: cabeza + torso/vestido + brazos + piernas.
  static Path _femalePath(double size, double cx) {
    final headR = size * 0.105;
    final headCy = size * 0.21;
    final shoulderY = headCy + headR + size * 0.015;
    final waistY = size * 0.48;
    final hemY = size * 0.72;
    final footY = size * 0.92;
    final shoulderW = size * 0.24;
    final waistW = size * 0.12;
    final hemW = size * 0.34;
    final armOut = size * 0.32;
    final armY = size * 0.46;

    final p = Path();
    p.addOval(Rect.fromCircle(center: Offset(cx, headCy), radius: headR));
    // Torso + falda (silueta única)
    p.moveTo(cx - size * 0.04, shoulderY);
    p.lineTo(cx - shoulderW / 2, shoulderY + size * 0.03);
    p.lineTo(cx - waistW / 2, waistY);
    p.lineTo(cx - hemW / 2, hemY);
    p.lineTo(cx + hemW / 2, hemY);
    p.lineTo(cx + waistW / 2, waistY);
    p.lineTo(cx + shoulderW / 2, shoulderY + size * 0.03);
    p.lineTo(cx + size * 0.04, shoulderY);
    p.close();
    // Brazos
    p.moveTo(cx - shoulderW / 2 + size * 0.02, shoulderY + size * 0.05);
    p.lineTo(cx - armOut, armY);
    p.lineTo(cx - armOut + size * 0.04, armY + size * 0.03);
    p.lineTo(cx - shoulderW / 2 + size * 0.05, shoulderY + size * 0.1);
    p.close();
    p.moveTo(cx + shoulderW / 2 - size * 0.02, shoulderY + size * 0.05);
    p.lineTo(cx + armOut, armY);
    p.lineTo(cx + armOut - size * 0.04, armY + size * 0.03);
    p.lineTo(cx + shoulderW / 2 - size * 0.05, shoulderY + size * 0.1);
    p.close();
    // Piernas bajo la falda
    p.moveTo(cx - size * 0.07, hemY);
    p.lineTo(cx - size * 0.1, footY);
    p.lineTo(cx - size * 0.03, footY);
    p.lineTo(cx - size * 0.02, hemY);
    p.close();
    p.moveTo(cx + size * 0.07, hemY);
    p.lineTo(cx + size * 0.1, footY);
    p.lineTo(cx + size * 0.03, footY);
    p.lineTo(cx + size * 0.02, hemY);
    p.close();
    return p;
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
