import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/app_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/widgets/route_back_button.dart';
import '../../content/domain/content_type.dart';
import '../data/remembrance_widget_preferences.dart';

class RemembranceWidgetSettingsPage extends ConsumerStatefulWidget {
  const RemembranceWidgetSettingsPage({super.key});
  @override
  ConsumerState<RemembranceWidgetSettingsPage> createState() =>
      _RemembranceWidgetSettingsPageState();
}

class _RemembranceWidgetSettingsPageState
    extends ConsumerState<RemembranceWidgetSettingsPage> {
  bool _loading = true, _busy = false, _dirty = false;
  int _loadVersion = 0;
  Object? _error;
  List<Map<String, Object?>> _cards = [];
  final _hiddenIds = <String>{}, _hiddenTypes = <String>{};
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final version = ++_loadVersion;
    final user = ref.read(accountSessionProvider)?.id;
    setState(() {
      _loading = user != null;
      _busy = false;
      _dirty = false;
      _error = null;
      _cards = [];
      _hiddenIds.clear();
      _hiddenTypes.clear();
    });
    if (user == null) return;
    try {
      final settings = await ref
          .read(remembranceWidgetPreferencesStoreProvider)
          .read(user);
      final cards = await ref
          .read(remembranceWidgetServiceProvider)
          .loadAvailable(user);
      if (!mounted ||
          version != _loadVersion ||
          ref.read(accountSessionProvider)?.id != user) {
        return;
      }
      final groups = <String, Map<String, Object?>>{};
      for (final card in cards) {
        groups.putIfAbsent(
          (card['groupId'] ?? card['id']) as String,
          () => card,
        );
      }
      setState(() {
        _cards = groups.values.toList();
        _hiddenIds.addAll(settings.hiddenIds);
        _hiddenTypes.addAll(settings.hiddenTypes);
        _loading = false;
      });
    } catch (error) {
      if (mounted &&
          version == _loadVersion &&
          ref.read(accountSessionProvider)?.id == user) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final user = ref.read(accountSessionProvider)?.id;
    if (user == null || _busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(remembranceWidgetPreferencesStoreProvider)
          .save(
            user,
            RemembranceWidgetPreferences(
              hiddenIds: Set.of(_hiddenIds),
              hiddenTypes: Set.of(_hiddenTypes),
            ),
          );
      await ref.read(remembranceWidgetServiceProvider).refresh(user);
      if (!mounted || ref.read(accountSessionProvider)?.id != user) return;
      setState(() {
        _busy = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ المحتوى الظاهر وتحديث الويدجت.')),
      );
    } catch (error) {
      if (mounted && ref.read(accountSessionProvider)?.id == user) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    }
  }

  Future<void> _addWidget() async {
    final user = ref.read(accountSessionProvider)?.id;
    if (user == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (_dirty) {
        await ref
            .read(remembranceWidgetPreferencesStoreProvider)
            .save(
              user,
              RemembranceWidgetPreferences(
                hiddenIds: Set.of(_hiddenIds),
                hiddenTypes: Set.of(_hiddenTypes),
              ),
            );
      }
      final service = ref.read(remembranceWidgetServiceProvider);
      await service.refresh(user);
      if (!mounted || ref.read(accountSessionProvider)?.id != user) return;
      final requested = await service.requestPin();
      if (!mounted || ref.read(accountSessionProvider)?.id != user) return;
      setState(() => _dirty = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            requested ? 'أكمل إضافة ويدجت الأذكار والإهداء من نافذة النظام.' : 'اضغط مطولاً على الشاشة الرئيسية، ثم اختر ويدجت الأذكار والإهداء.',
          ),
        ),
      );
    } catch (error) {
      if (mounted && ref.read(accountSessionProvider)?.id == user) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyMessage(error))));
      }
    } finally {
      if (mounted && ref.read(accountSessionProvider)?.id == user) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(accountSessionProvider.select((user) => user?.id), (_, _) {
      unawaited(_load());
    });
    final signedIn = ref.watch(accountSessionProvider) != null;
    final supported = ref
        .watch(remembranceWidgetServiceProvider)
        .runtime
        .isNativeMobile;
    return UnsavedChangesGuard(
      isDirty: _dirty,
      fallbackLocation: '/worship',
      child: Scaffold(
        appBar: AppBar(
          leading: const RouteBackButton(),
          title: const Text('ويدجت الشاشة الرئيسية'),
        ),
        bottomNavigationBar: _loading || !signedIn || _error != null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: _busy || !_dirty ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_busy ? 'جارٍ الحفظ…' : 'حفظ وتحديث الويدجت'),
                  ),
                ),
              ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (supported)
                        FilledButton.icon(
                          key: const ValueKey('add-remembrance-widget'),
                          onPressed: _busy || !signedIn || _error != null
                              ? null
                              : _addWidget,
                          icon: const Icon(Icons.add_to_home_screen),
                          label: const Text('إضافة ويدجت الأذكار والإهداء'),
                        )
                      else
                        const Text('إضافة الويدجت متاحة من تطبيق الموبايل.'),
                      const SizedBox(height: 20),
                      Text(
                        'المحتوى الظاهر في الويدجت',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'اختَر الأنواع والنصوص التي تظهر على شاشتك الرئيسية. الإعدادات محفوظة لهذا الحساب على هذا الجهاز.',
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final type in [
                            ContentType.azkar,
                            ContentType.dua,
                            ContentType.hadith,
                            ContentType.quran,
                            ContentType.tasbeeh,
                            ContentType.dedication,
                          ])
                            FilterChip(
                              label: Text(type.pluralLabelAr),
                              selected: !_hiddenTypes.contains(type.id),
                              onSelected: _busy
                                  ? null
                                  : (show) => setState(() {
                                      _dirty = true;
                                      show
                                          ? _hiddenTypes.remove(type.id)
                                          : _hiddenTypes.add(type.id);
                                    }),
                            ),
                        ],
                      ),
                      Row(
                        children: [
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _dirty = true;
                                    _hiddenIds.clear();
                                    _hiddenTypes.clear();
                                  }),
                            child: const Text('إظهار الكل'),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _dirty = true;
                                    _hiddenIds.addAll(
                                      _cards.map(
                                        (card) =>
                                            (card['groupId'] ?? card['id'])
                                                as String,
                                      ),
                                    );
                                  }),
                            child: const Text('إخفاء الكل'),
                          ),
                        ],
                      ),
                      if (_error != null) ...[
                        Text(friendlyMessage(_error)),
                        TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                      if (!_loading && _error == null && _cards.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'لا يوجد محتوى منشور في صفحاتك بعد. أضف النصوص إلى صفحتك وانشرها لتظهر هنا.',
                          ),
                        ),
                      for (final card in _cards)
                        SwitchListTile(
                          title: Text(card['title'] as String),
                          subtitle: Text(
                            card['text'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          value:
                              !_hiddenIds.contains(
                                card['groupId'] ?? card['id'],
                              ) &&
                              !_hiddenTypes.contains(card['kind']),
                          onChanged:
                              _busy || _hiddenTypes.contains(card['kind'])
                              ? null
                              : (show) => setState(() {
                                  _dirty = true;
                                  final id =
                                      (card['groupId'] ?? card['id']) as String;
                                  show
                                      ? _hiddenIds.remove(id)
                                      : _hiddenIds.add(id);
                                }),
                        ),
                      if (_cards.isEmpty && _error == null)
                        const Text('لا توجد نصوص منشورة متاحة حالياً.'),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
