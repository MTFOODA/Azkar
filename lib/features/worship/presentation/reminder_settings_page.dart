import '../../../core/widgets/route_back_button.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/design/app_palette.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/utils/app_exception.dart';
import '../../../core/utils/app_logger.dart';
import '../../notifications/domain/local_notification.dart';
import '../../prayer_times/domain/prayer_time_models.dart';
import '../../reminders/domain/reminder_preferences.dart';

class ReminderSettingsPage extends ConsumerStatefulWidget {
  const ReminderSettingsPage({super.key});

  @override
  ConsumerState<ReminderSettingsPage> createState() =>
      _ReminderSettingsPageState();
}

class _ReminderSettingsPageState extends ConsumerState<ReminderSettingsPage> {
  ReminderPreferences _preferences = ReminderPreferences.defaults;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final userId = ref.read(accountSessionProvider)?.id;
    if (userId == null) return;
    try {
      final local = await ref
          .read(reminderPreferencesLocalStoreProvider)
          .read(userId);
      if (!mounted) return;
      setState(() {
        _preferences = local?.preferences ?? ReminderPreferences.defaults;
        _loading = false;
      });
    } on Object catch (error, stackTrace) {
      AppLogger.warning('Reminder settings load failed', error, stackTrace);
      if (!mounted) return;
      setState(() => _loading = false);
      _message(
        'تعذّر تحميل الإعدادات. ${friendlyMessage(error)}',
        isError: true,
      );
    }
  }

  Future<void> _save(ReminderPreferences next) async {
    final userId = ref.read(accountSessionProvider)?.id;
    if (userId == null || _saving) return;
    setState(() {
      _saving = true;
      _preferences = next;
    });
    try {
      await ref
          .read(localReminderSchedulingEngineProvider)
          .saveLocalPreferencesAndReconcile(userId: userId, preferences: next);
      final result = await ref
          .read(reminderPreferencesSyncServiceProvider)
          .sync(userId);
      if (result.status == ReminderSyncStatus.conflict) {
        await _resolveConflict(userId, result);
      } else if (mounted) {
        setState(() => _preferences = result.preferences);
      }
      await ref.read(localReminderSchedulingEngineProvider).reconcile(userId);
      if (mounted && result.status == ReminderSyncStatus.offline) {
        _message('حُفظت التغييرات على هذا الجهاز وستُزامن عند الاتصال.');
      }
    } on Object catch (error, stackTrace) {
      AppLogger.warning('Reminder settings save failed', error, stackTrace);
      if (mounted) {
        _message(friendlyMessage(error), isError: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resolveConflict(
    String userId,
    ReminderSyncResult result,
  ) async {
    final remote = result.serverSnapshot;
    if (remote == null || !mounted) {
      _message('توجد تغييرات متعارضة؛ لم تُستبدل أي إعدادات.', isError: true);
      return;
    }
    final useLocal = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تعارض في إعدادات التذكير'),
        content: const Text(
          'تغيّرت الإعدادات على جهاز آخر. اختر النسخة التي تريد الاحتفاظ بها.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('استخدام إعدادات الحساب'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('الاحتفاظ بإعدادات هذا الجهاز'),
          ),
        ],
      ),
    );
    if (useLocal == null || !mounted) {
      if (mounted) {
        _message(
          'لم يُحسم التعارض؛ احتُفظ بالتعديلات المحلية دون استبدالها.',
          isError: true,
        );
      }
      return;
    }
    final selected = useLocal ? _preferences : remote.preferences;
    final resolved = await ref
        .read(reminderPreferencesSyncServiceProvider)
        .resolveConflict(
          userId: userId,
          preferences: selected,
          serverSnapshot: remote,
        );
    if (!mounted) return;
    setState(() => _preferences = resolved.preferences);
  }

  Future<void> _toggle({
    required bool value,
    required ReminderPreferences Function(bool value) update,
  }) => _save(update(value));

  Future<void> _pickTime({
    required String initial,
    required ReminderPreferences Function(String value) update,
  }) async {
    final parts = initial.split(':');
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts.first),
        minute: int.parse(parts.last),
      ),
      helpText: 'اختر وقت التذكير',
    );
    if (time == null) return;
    await _save(
      update(
        '${time.hour.toString().padLeft(2, '0')}:'
        '${time.minute.toString().padLeft(2, '0')}',
      ),
    );
  }

  Future<void> _editCustom([ReminderConfiguration? configuration]) async {
    if (configuration == null && _preferences.configurations.length >= 100) {
      _message('وصلت إلى الحد الأقصى للتذكيرات المخصصة.', isError: true);
      return;
    }
    final result = await showDialog<ReminderConfiguration>(
      context: context,
      builder: (context) => _CustomReminderDialog(initial: configuration),
    );
    if (result == null) return;
    final isDuplicate = _preferences.configurations.any((existing) {
      if (existing.id == configuration?.id) return false;
      return _sameSchedule(existing, result);
    });
    if (isDuplicate) {
      _message('يوجد تذكير مماثل بالنص والوقت والتكرار.', isError: true);
      return;
    }
    final configurations = _preferences.configurations
        .where((item) => item.id != configuration?.id)
        .followedBy(<ReminderConfiguration>[result])
        .toList(growable: false);
    await _save(_preferences.copyWith(configurations: configurations));
  }

  Future<void> _deleteCustom(ReminderConfiguration configuration) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف التذكير'),
        content: const Text('هل تريد حذف هذا التذكير؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _save(
      _preferences.copyWith(
        configurations: _preferences.configurations
            .where((item) => item.id != configuration.id)
            .toList(growable: false),
      ),
    );
  }

  bool _sameSchedule(ReminderConfiguration left, ReminderConfiguration right) {
    final leftRawDays = left.parameters['days'];
    final rightRawDays = right.parameters['days'];
    final leftDays = leftRawDays is List ? leftRawDays.join(',') : '';
    final rightDays = rightRawDays is List ? rightRawDays.join(',') : '';
    return left.kind == right.kind &&
        left.parameters['text'] == right.parameters['text'] &&
        left.parameters['time'] == right.parameters['time'] &&
        left.parameters['recurrence'] == right.parameters['recurrence'] &&
        leftDays == rightDays;
  }

  void _message(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const RouteBackButton(),
        title: const Text('إعدادات التذكير'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.all(AppPalette.spaceMd),
                  children: [
                    if (_saving) const LinearProgressIndicator(),
                    Card(
                      child: Column(
                        children: [
                          _toggleTile(
                            title: 'تنبيه عند دخول وقت الصلاة',
                            subtitle: 'حسب مواقيت المدينة والمنطقة الزمنية.',
                            value: _preferences.prayerTimeNotificationsEnabled,
                            update: (value) => _preferences.copyWith(
                              prayerTimeNotificationsEnabled: value,
                            ),
                          ),
                          _toggleTile(
                            title: 'تذكير بمتابعة الصلاة',
                            subtitle:
                                'تذكير بعد الصلاة، وواحد أخير عند الحاجة.',
                            value: _preferences.prayerRemindersEnabled,
                            update: (value) => _preferences.copyWith(
                              prayerRemindersEnabled: value,
                            ),
                          ),
                          _toggleTile(
                            title: 'تسبيح بعد الصلاة',
                            subtitle: _preferences.postPrayerTasbeehEnabled
                                ? 'التذكير بعد ${_preferences.postPrayerDelayMinutes} دقيقة.'
                                : 'لا يُفعّل تلقائياً.',
                            value: _preferences.postPrayerTasbeehEnabled,
                            update: (value) => _preferences.copyWith(
                              postPrayerTasbeehEnabled: value,
                            ),
                          ),
                          if (_preferences.postPrayerTasbeehEnabled)
                            ListTile(
                              contentPadding: const EdgeInsetsDirectional.only(
                                start: 72,
                                end: AppPalette.spaceMd,
                              ),
                              title: const Text('تأخير تذكير التسبيح'),
                              subtitle: Text(
                                '${_preferences.postPrayerDelayMinutes} دقيقة بعد إتمام الصلاة',
                              ),
                              trailing: DropdownButton<int>(
                                value: _preferences.postPrayerDelayMinutes,
                                items: const [0, 5, 10, 15, 20, 30, 60]
                                    .map(
                                      (minutes) => DropdownMenuItem(
                                        value: minutes,
                                        child: Text('$minutes د'),
                                      ),
                                    )
                                    .toList(growable: false),
                                onChanged: (minutes) {
                                  if (minutes != null) {
                                    _save(
                                      _preferences.copyWith(
                                        postPrayerDelayMinutes: minutes,
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          _toggleTile(
                            title: 'أذكار الصباح',
                            subtitle: 'الوقت: ${_preferences.morningAzkarTime}',
                            value: _preferences.morningAzkarEnabled,
                            update: (value) => _preferences.copyWith(
                              morningAzkarEnabled: value,
                            ),
                            onTime: () => _pickTime(
                              initial: _preferences.morningAzkarTime,
                              update: (time) =>
                                  _preferences.copyWith(morningAzkarTime: time),
                            ),
                          ),
                          _toggleTile(
                            title: 'أذكار المساء',
                            subtitle: 'الوقت: ${_preferences.eveningAzkarTime}',
                            value: _preferences.eveningAzkarEnabled,
                            update: (value) => _preferences.copyWith(
                              eveningAzkarEnabled: value,
                            ),
                            onTime: () => _pickTime(
                              initial: _preferences.eveningAzkarTime,
                              update: (time) =>
                                  _preferences.copyWith(eveningAzkarTime: time),
                            ),
                          ),
                          _toggleTile(
                            title: 'سورة الكهف يوم الجمعة',
                            subtitle: 'الوقت: ${_preferences.fridayKahfTime}',
                            value: _preferences.fridayKahfEnabled,
                            update: (value) =>
                                _preferences.copyWith(fridayKahfEnabled: value),
                            onTime: () => _pickTime(
                              initial: _preferences.fridayKahfTime,
                              update: (time) =>
                                  _preferences.copyWith(fridayKahfTime: time),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppPalette.spaceMd),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text('ساعات الهدوء'),
                            subtitle: Text(
                              _preferences.quietHoursStart == null
                                  ? 'غير مفعّلة'
                                  : '${_preferences.quietHoursStart} – ${_preferences.quietHoursEnd}',
                            ),
                            trailing: const Icon(Icons.schedule),
                            onTap: _pickQuietHours,
                          ),
                          if (_preferences.quietHoursStart != null)
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: TextButton(
                                onPressed: () => _save(
                                  _preferences.copyWith(clearQuietHours: true),
                                ),
                                child: const Text('إيقاف ساعات الهدوء'),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppPalette.spaceMd),
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            title: const Text('الأذكار والأدعية المخصصة'),
                            subtitle: const Text(
                              'نص ووقت وتكرار يومي أو أيام محددة.',
                            ),
                            trailing: IconButton(
                              tooltip: 'إضافة تذكير',
                              onPressed: () => _editCustom(),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                          ),
                          for (final item in _customConfigurations)
                            ListTile(
                              title: Text('${item.parameters['text']}'),
                              subtitle: Text(
                                '${item.parameters['time']} • '
                                '${_recurrenceText(item)}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              leading: Switch(
                                value: item.enabled,
                                onChanged: (enabled) => _save(
                                  _preferences.copyWith(
                                    configurations: _preferences.configurations
                                        .map(
                                          (current) => current.id == item.id
                                              ? ReminderConfiguration(
                                                  id: current.id,
                                                  kind: current.kind,
                                                  enabled: enabled,
                                                  parameters:
                                                      current.parameters,
                                                  memorialPageId:
                                                      current.memorialPageId,
                                                )
                                              : current,
                                        )
                                        .toList(growable: false),
                                  ),
                                ),
                              ),
                              trailing: PopupMenuButton<String>(
                                onSelected: (action) {
                                  if (action == 'edit') _editCustom(item);
                                  if (action == 'delete') {
                                    _deleteCustom(item);
                                  }
                                },
                                itemBuilder: (context) => const [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: Text('تعديل'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('حذف'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppPalette.spaceMd),
                    Card(
                      child: _toggleTile(
                        title: 'إخفاء محتوى الإشعار على شاشة القفل',
                        subtitle: 'يعرض إشعاراً عاماً بدلاً من نص التذكير.',
                        value: _preferences.hideNotificationContent,
                        update: (value) => _preferences.copyWith(
                          hideNotificationContent: value,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppPalette.spaceMd),
                    FilledButton.tonalIcon(
                      onPressed: () => context.push('/worship/notifications'),
                      icon: const Icon(Icons.notifications_active_outlined),
                      label: const Text('إعداد إذن الإشعارات'),
                    ),
                    TextButton.icon(
                      onPressed: () => context.push('/onboarding'),
                      icon: const Icon(Icons.info_outline),
                      label: const Text('التعريف بتطبيق أذكار'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  List<ReminderConfiguration> get _customConfigurations => _preferences
      .configurations
      .where(
        (item) => const <String>{
          'custom_remembrance',
          'custom_daily_remembrance',
          'custom_azkar',
          'custom_dua',
          'dua',
        }.contains(item.kind.trim().toLowerCase()),
      )
      .toList(growable: false);

  Widget _toggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required ReminderPreferences Function(bool value) update,
    VoidCallback? onTime,
  }) => ListTile(
    title: Text(title),
    subtitle: Text(subtitle),
    leading: Switch(
      value: value,
      onChanged: (next) => _toggle(value: next, update: update),
    ),
    trailing: onTime == null
        ? null
        : IconButton(
            tooltip: 'تغيير الوقت',
            onPressed: onTime,
            icon: const Icon(Icons.edit_calendar_outlined),
          ),
  );

  Future<void> _pickQuietHours() async {
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour:
            int.tryParse(
              _preferences.quietHoursStart?.split(':').first ?? '',
            ) ??
            22,
        minute:
            int.tryParse(_preferences.quietHoursStart?.split(':').last ?? '') ??
            0,
      ),
      helpText: 'بداية ساعات الهدوء',
    );
    if (start == null || !mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour:
            int.tryParse(_preferences.quietHoursEnd?.split(':').first ?? '') ??
            7,
        minute:
            int.tryParse(_preferences.quietHoursEnd?.split(':').last ?? '') ??
            0,
      ),
      helpText: 'نهاية ساعات الهدوء',
    );
    if (end == null) return;
    await _save(
      _preferences.copyWith(
        quietHoursStart:
            '${start.hour.toString().padLeft(2, '0')}:'
            '${start.minute.toString().padLeft(2, '0')}',
        quietHoursEnd:
            '${end.hour.toString().padLeft(2, '0')}:'
            '${end.minute.toString().padLeft(2, '0')}',
      ),
    );
  }

  String _recurrenceText(ReminderConfiguration item) {
    if (item.parameters['recurrence'] == 'daily') return 'يومي';
    const days = <int, String>{
      DateTime.saturday: 'السبت',
      DateTime.sunday: 'الأحد',
      DateTime.monday: 'الاثنين',
      DateTime.tuesday: 'الثلاثاء',
      DateTime.wednesday: 'الأربعاء',
      DateTime.thursday: 'الخميس',
      DateTime.friday: 'الجمعة',
    };
    final selected = item.parameters['days'];
    if (selected is! List) return 'أيام محددة';
    return selected
        .whereType<int>()
        .map((day) => days[day])
        .whereType<String>()
        .join('، ');
  }
}

class _CustomReminderDialog extends StatefulWidget {
  const _CustomReminderDialog({this.initial});

  final ReminderConfiguration? initial;

  @override
  State<_CustomReminderDialog> createState() => _CustomReminderDialogState();
}

class _CustomReminderDialogState extends State<_CustomReminderDialog> {
  late final TextEditingController _text;
  late final TextEditingController _time;
  late bool _daily;
  late bool _enabled;
  late Set<int> _days;
  late String _kind;
  String? _error;

  static const _weekdayOptions = <int, String>{
    DateTime.saturday: 'سبت',
    DateTime.sunday: 'أحد',
    DateTime.monday: 'اثنين',
    DateTime.tuesday: 'ثلاثاء',
    DateTime.wednesday: 'أربعاء',
    DateTime.thursday: 'خميس',
    DateTime.friday: 'جمعة',
  };

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _text = TextEditingController(text: '${initial?.parameters['text'] ?? ''}');
    _time = TextEditingController(
      text: '${initial?.parameters['time'] ?? '09:00'}',
    );
    _daily = initial?.parameters['recurrence'] != 'specific_days';
    _enabled = initial?.enabled ?? true;
    final days = initial?.parameters['days'];
    _days = days is List ? days.whereType<int>().toSet() : <int>{};
    _kind = initial?.kind == 'custom_dua' || initial?.kind == 'dua'
        ? 'custom_dua'
        : 'custom_remembrance';
  }

  @override
  void dispose() {
    _text.dispose();
    _time.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _text.text.trim();
    if (text.isEmpty || text.length > 500) {
      setState(() => _error = 'اكتب نصاً من 1 إلى 500 حرف.');
      return;
    }
    if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(_time.text.trim())) {
      setState(() => _error = 'أدخل الوقت بصيغة 24 ساعة، مثل 09:30.');
      return;
    }
    if (!_daily && _days.isEmpty) {
      setState(() => _error = 'اختر يوماً واحداً على الأقل.');
      return;
    }
    final existing = widget.initial;
    Navigator.pop(
      context,
      ReminderConfiguration(
        id: existing?.id ?? const Uuid().v4(),
        kind: _kind,
        enabled: _enabled,
        parameters: <String, Object?>{
          'text': text,
          'time': _time.text.trim(),
          'recurrence': _daily ? 'daily' : 'specific_days',
          if (!_daily) 'days': _days.toList()..sort(),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.initial == null ? 'تذكير مخصص جديد' : 'تعديل التذكير'),
    content: SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'custom_remembrance', label: Text('ذِكر')),
                ButtonSegment(value: 'custom_dua', label: Text('دعاء')),
              ],
              selected: {_kind},
              onSelectionChanged: (value) =>
                  setState(() => _kind = value.first),
            ),
            const SizedBox(height: AppPalette.spaceMd),
            TextField(
              controller: _text,
              maxLines: 4,
              maxLength: 500,
              decoration: const InputDecoration(labelText: 'النص'),
            ),
            const SizedBox(height: AppPalette.spaceSm),
            TextField(
              controller: _time,
              keyboardType: TextInputType.datetime,
              decoration: const InputDecoration(
                labelText: 'الوقت',
                hintText: '09:30',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تكرار يومي'),
              value: _daily,
              onChanged: (value) => setState(() => _daily = value),
            ),
            if (!_daily)
              Wrap(
                spacing: AppPalette.spaceXs,
                children: [
                  for (final entry in _weekdayOptions.entries)
                    FilterChip(
                      label: Text(entry.value),
                      selected: _days.contains(entry.key),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _days.add(entry.key);
                        } else {
                          _days.remove(entry.key);
                        }
                      }),
                    ),
                ],
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('تفعيل التذكير'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('إلغاء'),
      ),
      FilledButton(onPressed: _submit, child: const Text('حفظ')),
    ],
  );
}

class NotificationPermissionPage extends ConsumerStatefulWidget {
  const NotificationPermissionPage({super.key});

  @override
  ConsumerState<NotificationPermissionPage> createState() =>
      _NotificationPermissionPageState();
}

class _NotificationPermissionPageState
    extends ConsumerState<NotificationPermissionPage>
    with WidgetsBindingObserver {
  NotificationPermissionState? _permission;
  String? _permissionError;
  bool _busy = false;
  bool? _exactAlarmsGranted;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_readPermission());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_readPermission());
  }

  Future<void> _readPermission() async {
    try {
      final state = await ref
          .read(localNotificationServiceProvider)
          .permissionState();
      final exact = await ref
          .read(localNotificationServiceProvider)
          .exactAlarmPermissionState();
      if (mounted) {
        setState(() {
          _permission = state;
          _exactAlarmsGranted = exact;
          _permissionError = null;
        });
      }
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Notification permission state lookup failed',
        error,
        stackTrace,
      );
      if (mounted) {
        setState(() => _permissionError = 'تعذّر التحقق من إذن الإشعارات.');
      }
    }
  }

  Future<void> _request() async {
    setState(() => _busy = true);
    try {
      final state = await ref
          .read(localNotificationServiceProvider)
          .requestPermission();
      if (mounted) {
        setState(() {
          _permission = state;
          _permissionError = null;
        });
      }
      final userId = ref.read(accountSessionProvider)?.id;
      if (state == NotificationPermissionState.granted && userId != null) {
        await ref.read(localReminderSchedulingEngineProvider).reconcile(userId);
      }
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Notification permission request failed',
        error,
        stackTrace,
      );
      if (mounted) {
        setState(() => _permissionError = 'تعذّر طلب إذن الإشعارات.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر طلب إذن الإشعارات.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSettings() async {
    try {
      final opened = await Geolocator.openAppSettings();
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('افتح إعدادات التطبيق يدوياً من الجهاز.'),
          ),
        );
      }
    } on Object catch (error, stackTrace) {
      AppLogger.warning('Opening app settings failed', error, stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تعذّر فتح إعدادات الجهاز. افتحها يدويًا.'),
        ),
      );
    }
  }

  Future<void> _requestExactAlarms() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(localNotificationServiceProvider)
          .requestExactAlarmPermission();
      await _readPermission();
      final userId = ref.read(accountSessionProvider)?.id;
      if (userId != null) {
        await ref.read(localReminderSchedulingEngineProvider).reconcile(userId);
      }
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Could not enable exact prayer alarms.',
        error,
        stackTrace,
      );
      if (mounted) {
        setState(
          () => _permissionError = 'تعذّر فتح إعدادات المنبّهات الدقيقة.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _testNotification() async {
    final userId = ref.read(accountSessionProvider)?.id;
    if (userId == null) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(localNotificationServiceProvider)
          .schedule(
            LocalNotificationRequest(
              accountId: userId,
              stableKey: 'notification-test:v1',
              title: 'أذكار • اختبار الإشعارات',
              body: 'الإشعارات تعمل على جهازك.',
              scheduledAt: PrayerTimeZones.localDateTime(
                DateTime.now().add(const Duration(seconds: 10)),
                'UTC',
              ),
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('سيصلك إشعار تجريبي بعد نحو 10 ثوانٍ.')),
        );
      }
    } on Object catch (error, stackTrace) {
      AppLogger.warning(
        'Could not schedule test notification.',
        error,
        stackTrace,
      );
      if (mounted) {
        setState(() => _permissionError = 'تعذّر جدولة التنبيه التجريبي.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: const RouteBackButton(),
      title: const Text('إذن الإشعارات'),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(AppPalette.spaceLg),
          shrinkWrap: true,
          children: [
            Icon(
              Icons.notifications_active_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: AppPalette.spaceMd),
            Text(
              'تفعيل الإشعارات',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppPalette.spaceMd),
            const Text(
              'اسمح بالإشعارات لتصلك تذكيرات الصلاة والأذكار.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppPalette.spaceMd),
            Card(
              child: ListTile(
                leading: Icon(
                  _permission == NotificationPermissionState.granted
                      ? Icons.check_circle_outline
                      : Icons.notifications_outlined,
                ),
                title: Text(switch (_permission) {
                  NotificationPermissionState.granted => 'الإذن مفعّل',
                  NotificationPermissionState.denied => 'الإذن غير مفعّل',
                  NotificationPermissionState.unsupported =>
                    'الإشعارات غير مدعومة على هذا النظام',
                  null => 'جارٍ التحقق من الإذن',
                }),
              ),
            ),
            const SizedBox(height: AppPalette.spaceMd),
            if (_permission == NotificationPermissionState.denied)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _request,
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: Text(_busy ? 'جارٍ الطلب…' : 'السماح بالإشعارات'),
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : _openSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('فتح إعدادات الجهاز'),
                  ),
                ],
              ),
            if (_permissionError != null)
              Text(_permissionError!, textAlign: TextAlign.center),
            if (_permission == null && _permissionError != null)
              TextButton(
                onPressed: _readPermission,
                child: const Text('إعادة المحاولة'),
              ),
            const SizedBox(height: AppPalette.spaceSm),
            if (_permission == NotificationPermissionState.granted) ...[
              if (_exactAlarmsGranted != null)
                Card(
                  child: ListTile(
                    title: Text(
                      _exactAlarmsGranted!
                          ? 'تنبيهات الصلاة في موعدها مفعّلة'
                          : 'تفعيل تنبيهات الصلاة في موعدها',
                    ),
                    trailing: _exactAlarmsGranted!
                        ? const Icon(Icons.check_circle_outline)
                        : const Icon(Icons.alarm),
                    onTap: _busy || _exactAlarmsGranted!
                        ? null
                        : _requestExactAlarms,
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _busy ? null : _testNotification,
                icon: const Icon(Icons.notifications_outlined),
                label: const Text('اختبار الإشعارات'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
