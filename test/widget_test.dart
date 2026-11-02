import 'package:flutter_test/flutter_test.dart';
import 'package:gps_fmra/app.dart';
import 'package:gps_fmra/core/l10n/app_strings.dart';

void main() {
  testWidgets('Splash muestra marca GPS-FMRA y navega al login', (tester) async {
    await tester.pumpWidget(const GpsFmraApp());
    expect(find.text(AppStrings.appName), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.loginTitle), findsOneWidget);
  });
}
