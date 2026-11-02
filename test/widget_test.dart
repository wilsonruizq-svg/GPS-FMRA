import 'package:flutter_test/flutter_test.dart';
import 'package:gps_fmra/app.dart';
import 'package:gps_fmra/core/l10n/app_strings.dart';

void main() {
  testWidgets('Splash muestra marca GPS-FMRA', (tester) async {
    await tester.pumpWidget(const GpsFmraApp(supabaseReady: false));
    expect(find.text(AppStrings.appName), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1000));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.loginTitle), findsOneWidget);
  });
}
