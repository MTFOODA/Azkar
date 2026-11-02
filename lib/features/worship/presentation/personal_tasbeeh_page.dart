import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_palette.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../tasbeeh/domain/tasbeeh_counter.dart';

class PersonalTasbeehPage extends ConsumerStatefulWidget {
  const PersonalTasbeehPage({super.key});

  @override
  ConsumerState<PersonalTasbeehPage> createState() =>
      _PersonalTasbeehPageState();
}

class _PersonalTasbeehPageState extends ConsumerState<PersonalTasbeehPage> {
  static const _counterId = 'personal-post-prayer-v1';
  TasbeehCounter? _counter;
  BigInt _count = BigInt.zero;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    final userId = ref.read(accountSessionProvider)?.id;
    if (userId == null) return;
    _counter = TasbeehCounter(
      store: ref.read(tasbeehCounterStoreProvider),
      tasbeehId: _counterId,
      pageId: 'worship-account:$userId',
      onChanged: (value) {
        if (mounted) {
          setState(() {
            _count = value;
            _ready = true;
          });
        }
      },
      onError: (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      },
    )..load();
  }

  @override
  void dispose() {
    _counter?.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تصفير التسبيح'),
        content: const Text('سيُصفّر هذا العدّاد الشخصي فقط.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('تصفير'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _counter?.reset();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تسبيح بعد الصلاة')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(AppPalette.spaceLg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.spa_outlined,
                size: 58,
                color: Theme.of(context).colorScheme.secondary,
              ),
              const SizedBox(height: AppPalette.spaceLg),
              Text(
                'سبحان الله وبحمده',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppPalette.spaceLg),
              Semantics(
                label: 'عدد التسبيحات',
                value: _count.toString(),
                child: Text(
                  _count.toString(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: AppPalette.spaceXl),
              FilledButton(
                onPressed: _ready ? _counter?.increment : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(72),
                ),
                child: const Text('تسبيح +'),
              ),
              const SizedBox(height: AppPalette.spaceSm),
              TextButton.icon(
                onPressed: _ready ? _reset : null,
                icon: const Icon(Icons.restart_alt),
                label: const Text('تصفير العدّاد الشخصي'),
              ),
              const SizedBox(height: AppPalette.spaceMd),
              Text(
                'هذا العدّاد مستقل عن عدّادات صفحات التذكار.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
