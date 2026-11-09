import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/app_logger.dart';

/// Prayer widget controls live with the prayer calendar they publish.
class PrayerWidgetActions extends ConsumerStatefulWidget {
  const PrayerWidgetActions({super.key});

  @override
  ConsumerState<PrayerWidgetActions> createState() =>
      _PrayerWidgetActionsState();
}

class _PrayerWidgetActionsState extends ConsumerState<PrayerWidgetActions> {
  bool _busy = false;

  Future<void> _update({bool pin = false}) async {
    final user = ref.read(accountSessionProvider)?.id;
    if (user == null || _busy) return;
    setState(() => _busy = true);
    String message;
    try {
      final service = ref.read(prayerHomeWidgetServiceProvider);
      await service.refresh(user);
      if (!mounted || ref.read(accountSessionProvider)?.id != user) return;
      final requested = pin && await service.requestPin();
      message = pin
          ? requested
                ? 'أكمل إضافة ويدجت الصلاة من نافذة النظام.'
                : 'اضغط مطولاً على الشاشة الرئيسية، ثم اختر ويدجت أذكار لمواقيت الصلاة.'
          : 'تم تحديث ويدجت مواقيت الصلاة.';
    } on Object catch (error, stackTrace) {
      AppLogger.warning('Prayer widget setup failed.', error, stackTrace);
      message = 'تعذّر تجهيز ويدجت الصلاة. راجع الموقع والاتصال وحاول مجدداً.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted || ref.read(accountSessionProvider)?.id != user) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(prayerHomeWidgetServiceProvider).isSupported) {
      return const SizedBox.shrink();
    }
    final signedIn = ref.watch(accountSessionProvider) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          key: const ValueKey('add-prayer-widget'),
          onPressed: _busy || !signedIn ? null : () => _update(pin: true),
          icon: const Icon(Icons.add_to_home_screen),
          label: const Text('إضافة مواقيت الصلاة إلى الشاشة الرئيسية'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('refresh-prayer-widget'),
          onPressed: _busy || !signedIn ? null : _update,
          icon: const Icon(Icons.refresh),
          label: const Text('تحديث ويدجت مواقيت الصلاة'),
        ),
        if (_busy) const LinearProgressIndicator(),
      ],
    );
  }
}
