import 'package:flutter_test/flutter_test.dart';
import 'package:gps_fmra/modules/groups/invite_token.dart';

void main() {
  test('normalize quita prefijo deep link stub', () {
    expect(
      InviteToken.normalize('gpsfmra://invite/AbCdEfGh1234'),
      'AbCdEfGh1234',
    );
    expect(InviteToken.normalize('  TokenSolo  '), 'TokenSolo');
  });

  test('hashToken es SHA-256 hex estable', () {
    final h1 = InviteToken.hashToken('AbCdEfGh1234');
    final h2 = InviteToken.hashToken('gpsfmra://invite/AbCdEfGh1234');
    expect(h1, h2);
    expect(h1.length, 64);
    expect(RegExp(r'^[a-f0-9]+$').hasMatch(h1), isTrue);
  });

  test('linkStub construye esquema gpsfmra', () {
    expect(
      InviteToken.linkStub('AbCdEfGh1234'),
      'gpsfmra://invite/AbCdEfGh1234',
    );
  });
}
