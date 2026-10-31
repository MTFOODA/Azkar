import 'package:azkar/core/config/supabase_configuration_error_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('configuration error explains missing settings without values', (
    tester,
  ) async {
    await tester.pumpWidget(
      const SupabaseConfigurationErrorPage(
        missingSettings: [
          'SUPABASE_URL',
          'SUPABASE_ANON_KEY (anon/publishable key)',
        ],
      ),
    );

    expect(find.text('إعداد Supabase غير مكتمل'), findsOneWidget);
    expect(find.textContaining('لم يتم الاتصال بـ Supabase'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsOneWidget);
    expect(find.textContaining('anon/publishable key'), findsOneWidget);
    expect(find.text('تسجيل الدخول'), findsNothing);
    expect(find.text('إنشاء الحساب'), findsNothing);
  });
}
