import 'package:flutter/material.dart';

import '../design/app_palette.dart';

class SupabaseConfigurationErrorPage extends StatelessWidget {
  const SupabaseConfigurationErrorPage({
    required this.missingSettings,
    super.key,
  });

  final List<String> missingSettings;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppPalette.lightPrimary,
        brightness: Brightness.light,
      ),
    ),
    home: Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_outlined, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'إعداد Supabase غير مكتمل',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'لم يتم الاتصال بـ Supabase. لن تُستخدم بيانات تجريبية '
                  'بدلًا من خدمة المصادقة.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'الإعدادات الناقصة: ${missingSettings.join('، ')}',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                ),
                const SizedBox(height: 12),
                const Text(
                  'شغّل AZKAR باستخدام ملف config/dev.json من ملف التشغيل '
                  'في VS Code أو عبر scripts\\run_android_dev.ps1.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'لتفعيل وضع العرض دون اتصال عمدًا، استخدم '
                  'AZKAR_DEMO_MODE=true.',
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
