import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Redimensiona y comprime avatares antes de subir a Storage.
abstract final class AvatarCompress {
  /// Lado máximo del borde más largo (px).
  static const maxEdge = 768;

  /// Calidad JPEG moderada (0–100).
  static const jpegQuality = 72;

  /// Tope blando post-compresión (~900 KiB); si queda grande, baja calidad.
  static const softMaxBytes = 900 * 1024;

  /// Devuelve JPEG redimensionado. Lanza [FormatException] si no es imagen.
  static Uint8List compress(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException(
        'No se pudo leer la imagen. Prueba con otra foto.',
      );
    }

    final oriented = img.bakeOrientation(decoded);
    final longest = oriented.width > oriented.height
        ? oriented.width
        : oriented.height;

    img.Image sized = oriented;
    if (longest > maxEdge) {
      if (oriented.width >= oriented.height) {
        sized = img.copyResize(
          oriented,
          width: maxEdge,
          interpolation: img.Interpolation.average,
        );
      } else {
        sized = img.copyResize(
          oriented,
          height: maxEdge,
          interpolation: img.Interpolation.average,
        );
      }
    }

    var quality = jpegQuality;
    var out = Uint8List.fromList(img.encodeJpg(sized, quality: quality));
    while (out.lengthInBytes > softMaxBytes && quality > 45) {
      quality -= 10;
      out = Uint8List.fromList(img.encodeJpg(sized, quality: quality));
    }
    return out;
  }
}
