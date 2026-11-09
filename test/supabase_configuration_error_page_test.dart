import 'package:azkar/core/config/supabase_configuration_error_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('configuration error hides technical setup details', (
    tester,
  ) async {
    await tester.pumpWidget(const SupabaseConfigurationErrorPage());

    expect(find.text('تعذّر تهيئة التطبيق'), findsOneWidget);
    expect(find.textContaining('لا يمكن تشغيل التطبيق الآن'), findsOneWidget);
    expect(find.textContaining('SUPABASE_URL'), findsNothing);
    expect(find.textContaining('dart-define'), findsNothing);
    expect(find.textContaining('AZKAR_DEMO_MODE'), findsNothing);
    expect(find.text('تسجيل الدخول'), findsNothing);
    expect(find.text('إنشاء الحساب'), findsNothing);
  });
}
