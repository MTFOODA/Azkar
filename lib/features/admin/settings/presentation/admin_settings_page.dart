import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/app_config.dart';
import '../../../../core/design/app_palette.dart';
import '../../../../core/providers/app_providers.dart';
import '../../../../core/widgets/state_views.dart';
import '../../dashboard/presentation/admin_shell.dart';

/// Operational settings and diagnostics. Secrets are deliberately never shown.
class AdminSettingsPage extends ConsumerWidget {
  const AdminSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(adminSessionProvider);
    final demo = ref.watch(isDemoBackendProvider);
    final storage = ref.watch(tasbeehCounterStoreProvider);
    return SingleChildScrollView(
      child: AdminPageContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              title: 'الإعدادات',
              subtitle: 'معلومات التشغيل والتكوين الآمن.',
            ),
            const SizedBox(height: AppPalette.spaceLg),
            Card(
              elevation: 0,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.cloud_outlined),
                    title: const Text('وضع البيانات'),
                    subtitle: Text(
                      demo
                          ? 'وضع العرض التجريبي المحلي — لا يوجد اتصال Supabase'
                          : 'Supabase / PostgreSQL مع سياسات RLS',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: const Text('الجلسة الحالية'),
                    subtitle: Text(session?.email ?? 'غير مسجل'),
                  ),
                  ListTile(
                    leading: const Icon(Icons.storage_outlined),
                    title: const Text('تخزين عدّادات التسبيح'),
                    subtitle: Text(
                      '${storage.backendLabel}\nلا تُرسل العدّادات إلى الخادم.',
                    ),
                  ),
                  ListTile(
                    leading: const Icon(Icons.link_outlined),
                    title: const Text('الرابط العام المُعدّ'),
                    subtitle: Text(AppConfig.siteBaseUrl),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppPalette.spaceLg),
            if (demo)
              const Card(
                elevation: 0,
                child: Padding(
                  padding: EdgeInsets.all(AppPalette.spaceLg),
                  child: Text(
                    'تنبيه: وضع العرض التجريبي مخصص للتطوير والاختبار فقط. '
                    'لبيانات حقيقية وصلاحيات إدارية آمنة، اربط المشروع بـ Supabase '
                    'واتبع دليل الإعداد في docs/SUPABASE_SETUP.md.',
                  ),
                ),
              ),
            const SizedBox(height: AppPalette.spaceLg),
            const Card(
              elevation: 0,
              child: Padding(
                padding: EdgeInsets.all(AppPalette.spaceLg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تزويد المشرفين',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'لا يوجد تسجيل ذاتي للمشرفين. أنشئ المستخدم في Supabase Auth، '
                      'ثم أضف سجلًا نشطًا في admin_profiles باستخدام حساب مالك أو SQL آمن. '
                      'لا تضع مفتاح service-role داخل تطبيق Flutter.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppPalette.spaceLg),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(adminSessionProvider.notifier).signOut(),
              icon: const Icon(Icons.logout_outlined),
              label: const Text('تسجيل الخروج'),
            ),
          ],
        ),
      ),
    );
  }
}
