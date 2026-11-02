import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Utilidades de token de invitación (cliente).
/// En BD solo se guarda [hashToken]; el texto en claro se muestra una vez.
abstract final class InviteToken {
  static const deepLinkPrefix = 'gpsfmra://invite/';

  /// Normaliza pegado de código o deep link stub.
  static String normalize(String raw) {
    var t = raw.trim();
    final lower = t.toLowerCase();
    if (lower.startsWith(deepLinkPrefix)) {
      t = t.substring(deepLinkPrefix.length).trim();
    }
    return t;
  }

  static bool isPlausible(String raw) {
    final t = normalize(raw);
    return t.length >= 8;
  }

  static String hashToken(String plainOrLink) {
    final plain = normalize(plainOrLink);
    return sha256.convert(utf8.encode(plain)).toString();
  }

  static String linkStub(String plainToken) =>
      '$deepLinkPrefix${normalize(plainToken)}';
}
