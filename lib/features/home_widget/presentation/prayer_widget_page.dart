import '../../../core/widgets/route_back_button.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/app_logger.dart';

class PrayerWidgetPage extends ConsumerStatefulWidget {
  const PrayerWidgetPage({super.key});

  @override
  ConsumerState<PrayerWidgetPage> createState() => _PrayerWidgetPageState();
}

class _PrayerWidgetPageState extends ConsumerState<PrayerWidgetPage> {
  bool _busy = false;
  String? _message;

  Future<void> _addRemembrance() async {
    final user = ref.read(accountSessionProvider)?.id;
    if (user == null) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(remembranceWidgetServiceProvider);
      await service.refresh(user);
      final requested = await service.requestPin();
      if (mounted) {
        setState(
          () => _message = requested
              ? 'أكمل إضافة ويدجت الأذكار من نافذة النظام.'
              : 'من قائمة الويدجت اختار «أذكار • دعاء وإهداء».',
        );
      }
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Could not prepare remembrance widget.',
        error,
        stackTrace,
      );
      if (mounted) {
        setState(
          () => _message = 'تعذّر تحميل الأذكار. راجع الاتصال وحاول مرة أخرى.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _update({bool pin = false}) async {
    final userId = ref.read(accountSessionProvider)?.id;
    if (userId == null) return;
    setState(() => _busy = true);
    try {
      final service = ref.read(prayerHomeWidgetServiceProvider);
      await service.refresh(userId);
      final requested = pin && await service.requestPin();
      if (!mounted) return;
      setState(
        () => _message = pin
            ? requested
                  ? 'أكمل إضافة الويدجت من نافذة النظام.'
                  : 'اضغط مطولاً على الشاشة الرئيسية، ثم اختر الويدجت وابحث عن أذكار.'
            : 'تم تحديث الويدجت. فعّل الموقع الحالي إذا لم تظهر المواقيت.',
      );
    } on Object catch (error, stackTrace) {
      AppLogger.warning('Widget setup failed.', error, stackTrace);
      if (mounted) {
        setState(
          () => _message =
              'تعذّر تحديث الويدجت. راجع الموقع والاتصال ثم حاول مجدداً.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = ref.read(prayerHomeWidgetServiceProvider).isSupported;
    return Scaffold(
      appBar: AppBar(
        leading: const RouteBackButton(),
        title: const Text('ويدجت الشاشة الرئيسية'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.widgets_outlined, size: 64),
              const SizedBox(height: 20),
              const Text(
                'مواقيت الصلاة على شاشتك الرئيسية',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'المواقيت الستة في صف واحد، واللوجو أقصى اليمين قبل التاريخين، والساعة في المنتصف. الحجم والخطوط يتكيفان مع مساحة الويدجت حسب توقيت موقعك.',
              ),
              const SizedBox(height: 24),
              if (supported) ...[
                FilledButton.icon(
                  onPressed: _busy ? null : () => _update(pin: true),
                  icon: const Icon(Icons.add_to_home_screen),
                  label: const Text('إضافة إلى الشاشة الرئيسية'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _update,
                  icon: const Icon(Icons.refresh),
                  label: const Text('تحديث الويدجت'),
                ),
                const Text(
                  'لو بقيت مساحة فارغة تحت ويدجت الصلاة بعد التحديث، اضغط عليها مطولًا وارفع حافتها السفلية. اللانشر قد يحتفظ بالحجم القديم؛ ويمكن حذف الويدجت وإضافتها مجددًا لتطبيق المقاس الجديد.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 24),
                Text(
                  'الأذكار والدعاء والإهداء',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'كروت تتبدّل كل 7 ثوانٍ والشاشة مفتوحة؛ اسحب لفوق للتنقّل يدوياً. اختَر النصوص التي تظهر أو تختفي من إعدادات المحتوى. قد يؤخر النظام التبديل عند تقييد الطاقة أو المنبّهات الدقيقة.',
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy ? null : _addRemembrance,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('إضافة ويدجت الأذكار والإهداء'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => context.push('/worship/widget/content'),
                  icon: const Icon(Icons.checklist),
                  label: const Text('اختيار المحتوى الظاهر في الويدجت'),
                ),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => context.push('/worship/notifications'),
                  icon: const Icon(Icons.alarm_on_outlined),
                  label: const Text('إعدادات إذن المنبّهات الدقيقة'),
                ),
              ] else
                const Text('الويدجت متاحة في تطبيق الموبايل على أندرويد وiOS.'),
              if (_busy) const LinearProgressIndicator(),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_message!, textAlign: TextAlign.center),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
