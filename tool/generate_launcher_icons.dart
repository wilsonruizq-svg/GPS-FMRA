// Genera mipmaps + adaptive icon Android.
//
// Uso:
//   dart run tool/generate_launcher_icons.dart
//   dart run tool/generate_launcher_icons.dart --option a|b|c|d|b-rounded|e|f|g
//   dart run tool/generate_launcher_icons.dart --source path/to/logo.jpg
//
// NO finalizar launcher hasta confirmación de Wilson (ver docs/ICONO_OPCIONES_ES.md).
import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final logoPath = File(_resolveSource(args));
  if (!logoPath.existsSync()) {
    stderr.writeln('Falta ${logoPath.path}');
    stderr.writeln(
      'Opciones: --option a|b|b-rounded|c|d|e|f|g  o  --source <archivo>  '
      '(default: assets/branding/logo-gps-fmra-v2.jpg — provisional)',
    );
    exit(1);
  }
  stdout.writeln('Fuente: ${logoPath.path}');

  final decoded = img.decodeImage(logoPath.readAsBytesSync());
  if (decoded == null) {
    stderr.writeln('No se pudo decodificar el logo');
    exit(1);
  }
  final logo = img.bakeOrientation(decoded);
  stdout.writeln('Logo fuente: ${logo.width}x${logo.height}');

  // Azul del disco del logo (evita el anillo blanco del borde).
  // Muestra a ~18% del radio desde el centro en horizontal.
  final bgSample = logo.getPixelSafe(
    (logo.width * 0.18).round(),
    logo.height ~/ 2,
  );
  var bgColor = img.ColorRgba8(
    bgSample.r.toInt(),
    bgSample.g.toInt(),
    bgSample.b.toInt(),
    255,
  );
  // Fallback de marca si la muestra no es azul dominante.
  if (bgColor.b.toInt() < 80 ||
      bgColor.b.toInt() <= bgColor.r.toInt() + 20) {
    bgColor = img.ColorRgba8(0x0B, 0x2A, 0x4A, 255); // AppColors.deepBlue
  }
  stdout.writeln(
    'Fondo adaptive ≈ '
    '#${bgColor.r.toInt().toRadixString(16).padLeft(2, '0')}'
    '${bgColor.g.toInt().toRadixString(16).padLeft(2, '0')}'
    '${bgColor.b.toInt().toRadixString(16).padLeft(2, '0')}',
  );

  // Densidades legacy ic_launcher (dp * density).
  const legacy = <String, int>{
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
  };

  // Foreground adaptive: canvas 108dp; safe zone ~72dp centrado.
  const adaptive = <String, int>{
    'mipmap-mdpi': 108,
    'mipmap-hdpi': 162,
    'mipmap-xhdpi': 216,
    'mipmap-xxhdpi': 324,
    'mipmap-xxxhdpi': 432,
  };

  final res = Directory('android/app/src/main/res');

  for (final e in legacy.entries) {
    final dir = Directory('${res.path}/${e.key}')..createSync(recursive: true);
    final sized = _fitContain(logo, e.value, e.value);
    File('${dir.path}/ic_launcher.png')
        .writeAsBytesSync(img.encodePng(sized));
    // Round icon = mismo asset (logo ya es circular).
    File('${dir.path}/ic_launcher_round.png')
        .writeAsBytesSync(img.encodePng(sized));
    stdout.writeln('OK ${e.key}/ic_launcher.png (${e.value}px)');
  }

  for (final e in adaptive.entries) {
    final dir = Directory('${res.path}/${e.key}')..createSync(recursive: true);
    final canvas = e.value;
    // Logo ocupa ~72/108 del canvas (safe zone) para no recortar texto/pin.
    final content = (canvas * 72 / 108).round();
    final fg = img.Image(width: canvas, height: canvas);
    img.fill(fg, color: img.ColorRgba8(0, 0, 0, 0));
    final fitted = _fitContain(logo, content, content);
    final ox = (canvas - fitted.width) ~/ 2;
    final oy = (canvas - fitted.height) ~/ 2;
    img.compositeImage(fg, fitted, dstX: ox, dstY: oy);
    File('${dir.path}/ic_launcher_foreground.png')
        .writeAsBytesSync(img.encodePng(fg));

    final bg = img.Image(width: canvas, height: canvas);
    img.fill(bg, color: bgColor);
    File('${dir.path}/ic_launcher_background.png')
        .writeAsBytesSync(img.encodePng(bg));
    stdout.writeln('OK ${e.key}/ic_launcher_foreground.png (${canvas}px)');
  }

  final anyDpi = Directory('${res.path}/mipmap-anydpi-v26')
    ..createSync(recursive: true);
  File('${anyDpi.path}/ic_launcher.xml').writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
'''.trimLeft());
  File('${anyDpi.path}/ic_launcher_round.xml').writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@mipmap/ic_launcher_background"/>
    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>
</adaptive-icon>
'''.trimLeft());

  // values/colors.xml helper (por si se usa color drawable después).
  final values = Directory('${res.path}/values')..createSync(recursive: true);
  final colorsFile = File('${values.path}/colors.xml');
  final hex =
      '#FF${bgColor.r.toInt().toRadixString(16).padLeft(2, '0')}'
      '${bgColor.g.toInt().toRadixString(16).padLeft(2, '0')}'
      '${bgColor.b.toInt().toRadixString(16).padLeft(2, '0')}';
  colorsFile.writeAsStringSync('''
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">$hex</color>
</resources>
'''.trimLeft());

  stdout.writeln('Adaptive XML + colors listos. Fondo $hex');
}

String _resolveSource(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--source' && i + 1 < args.length) {
      return args[i + 1];
    }
    if (a.startsWith('--source=')) {
      return a.substring('--source='.length);
    }
    if (a == '--option' && i + 1 < args.length) {
      return _optionPath(args[i + 1]);
    }
    if (a.startsWith('--option=')) {
      return _optionPath(a.substring('--option='.length));
    }
  }
  // Provisional hasta que Wilson elija (E/F/G preferidos: squircle).
  return 'assets/branding/logo-gps-fmra-v2.jpg';
}

String _optionPath(String raw) {
  var key = raw.trim().toLowerCase();
  key = key
      .replaceFirst(RegExp(r'^opcion[-_]?'), '')
      .replaceFirst(RegExp(r'^option[-_]?'), '');
  // Alias: b_rounded / brownded → b-rounded
  key = key.replaceAll('_', '-');
  if (key == 'brounded') key = 'b-rounded';
  if (key == 'pin') key = 'e';
  if (key == 'radar') key = 'f';
  if (key == 'monogram' || key == 'g-monogram') key = 'g';
  const map = {
    'a': 'assets/branding/icon-opciones/icon-opcion-a.jpg',
    'b': 'assets/branding/icon-opciones/icon-opcion-b.jpg',
    'b-rounded': 'assets/branding/icon-opciones/icon-opcion-b-rounded.jpg',
    'c': 'assets/branding/icon-opciones/icon-opcion-c.jpg',
    'd': 'assets/branding/icon-opciones/icon-opcion-d.jpg',
    'e': 'assets/branding/icon-opciones/icon-e-pin.jpg',
    'f': 'assets/branding/icon-opciones/icon-f-radar.jpg',
    'g': 'assets/branding/icon-opciones/icon-g-monogram.jpg',
  };
  final path = map[key];
  if (path == null) {
    stderr.writeln(
      'Opción no válida: $raw (usa a, b, b-rounded, c, d, e, f o g)',
    );
    exit(1);
  }
  return path;
}

img.Image _fitContain(img.Image src, int maxW, int maxH) {
  final scale = (maxW / src.width < maxH / src.height)
      ? maxW / src.width
      : maxH / src.height;
  final w = (src.width * scale).round().clamp(1, maxW);
  final h = (src.height * scale).round().clamp(1, maxH);
  return img.copyResize(
    src,
    width: w,
    height: h,
    interpolation: img.Interpolation.average,
  );
}
