import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gps_fmra/modules/profiles/avatar_compress.dart';
import 'package:image/image.dart' as img;

void main() {
  group('AvatarCompress', () {
    Uint8List _png(int w, int h) {
      final image = img.Image(width: w, height: h);
      img.fill(image, color: img.ColorRgb8(40, 120, 200));
      return Uint8List.fromList(img.encodePng(image));
    }

    // Tope razonable para avatar comprimido en tests (sólido plano ≈ pocos KB).
    const softCapBytes = 200 * 1024;

    test('reduce borde largo a ≤ maxEdge y produce JPEG', () {
      final raw = _png(1600, 900);
      final out = AvatarCompress.compress(raw);
      final decoded = img.decodeJpg(out);
      expect(decoded, isNotNull);
      final longest =
          decoded!.width > decoded.height ? decoded.width : decoded.height;
      expect(longest, lessThanOrEqualTo(AvatarCompress.maxEdge));
      expect(decoded.width, 768);
      expect(decoded.height, 432);
      expect(out.lengthInBytes, lessThan(softCapBytes));
    });

    test('imagen ya pequeña no se agranda', () {
      final raw = _png(200, 200);
      final out = AvatarCompress.compress(raw);
      final decoded = img.decodeJpg(out)!;
      expect(decoded.width, 200);
      expect(decoded.height, 200);
    });

    test('bytes inválidos → FormatException', () {
      expect(
        () => AvatarCompress.compress(Uint8List.fromList([1, 2, 3])),
        throwsFormatException,
      );
    });
  });
}
