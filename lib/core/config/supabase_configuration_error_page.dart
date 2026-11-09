import 'package:flutter/material.dart';

import '../design/app_palette.dart';

class SupabaseConfigurationErrorPage extends StatelessWidget {
  const SupabaseConfigurationErrorPage({super.key});

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
                  'تعذّر تهيئة التطبيق',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'لا يمكن تشغيل التطبيق الآن. يُرجى المحاولة لاحقًا أو '
                  'التواصل مع الدعم.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
