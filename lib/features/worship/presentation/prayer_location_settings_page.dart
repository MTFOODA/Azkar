import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_palette.dart';
import '../../../core/providers/app_providers.dart';
import '../../prayer_times/data/current_prayer_location_service.dart';
import '../../prayer_times/domain/prayer_time_errors.dart';
import '../../prayer_times/domain/prayer_time_models.dart';
import '../../reminders/domain/reminder_preferences.dart';

class PrayerLocationSettingsPage extends ConsumerStatefulWidget {
  const PrayerLocationSettingsPage({super.key});

  @override
  ConsumerState<PrayerLocationSettingsPage> createState() =>
      _PrayerLocationSettingsPageState();
}

class _PrayerLocationSettingsPageState
    extends ConsumerState<PrayerLocationSettingsPage> {
  final _city = TextEditingController();
  final _country = TextEditingController();
  final _countryCode = TextEditingController();
  final _timezone = TextEditingController();
  ReminderPreferences _preferences = ReminderPreferences.defaults;
  PrayerLocation? _location;
  PrayerCalendar? _calendar;
  PrayerCalculationMethod? _method;
  AsrCalculationMethod _asrMethod = AsrCalculationMethod.standard;
  bool _loading = true;
  bool _busy = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _city.dispose();
    _country.dispose();
    _countryCode.dispose();
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = ref.read(accountSessionProvider)?.id;
    if (userId == null) return;
    try {
      final local = await ref
          .read(reminderPreferencesLocalStoreProvider)
          .read(userId);
      final preferences = local?.preferences ?? ReminderPreferences.defaults;
      final location = await ref
          .read(localPrayerScheduleLocationStoreProvider)
          .resolve(userId: userId, preferences: preferences);
      if (!mounted) return;
      setState(() {
        _preferences = preferences;
        _location = location;
        _city.text = preferences.manualCity ?? '';
        _country.text = preferences.manualCountry ?? '';
        _countryCode.text = preferences.manualCountryCode ?? '';
        _timezone.text = preferences.timezoneId ?? '';
        _method = preferences.calculationMethod;
        _asrMethod = preferences.asrMethod;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _saveManualLocation() async {
    final city = _city.text.trim();
    final country = _country.text.trim();
    final code = _countryCode.text.trim();
    final timezoneId = _timezone.text.trim();
    if (city.isEmpty || country.isEmpty) {
      _message('أدخل اسم المدينة والدولة.', isError: true);
      return;
    }
    if (code.isNotEmpty && !RegExp(r'^[A-Za-z]{2}$').hasMatch(code)) {
      _message('رمز الدولة يجب أن يتكون من حرفين مثل EG.', isError: true);
      return;
    }
    try {
      final selectedLocation = PrayerLocation.manualCity(
        city: city,
        country: country,
        countryCode: code.isEmpty ? null : code,
        timezoneId: timezoneId.isEmpty ? null : timezoneId,
      );
      final next = _preferences.copyWith(
        manualCity: city,
        manualCountry: country,
        manualCountryCode: code.isEmpty ? null : code,
        clearManualCountryCode: code.isEmpty,
        timezoneId: timezoneId.isEmpty ? null : timezoneId,
        clearTimezoneId: timezoneId.isEmpty,
        clearManualLocation: false,
        calculationMethod:
            _method ?? PrayerCalculationMethod.forLocation(selectedLocation),
        asrMethod: _asrMethod,
      );
      final saved = await _savePreferences(next);
      if (saved == null) return;
      final userId = ref.read(accountSessionProvider)!.id;
      await ref
          .read(localPrayerScheduleLocationStoreProvider)
          .clearDeviceLocation(userId);
      final location = await ref
          .read(localPrayerScheduleLocationStoreProvider)
          .resolve(userId: userId, preferences: saved);
      if (!mounted) return;
      setState(() {
        _preferences = saved;
        _location = location;
        _method = saved.calculationMethod;
        _calendar = null;
        _city.text = saved.manualCity ?? '';
        _country.text = saved.manualCountry ?? '';
        _countryCode.text = saved.manualCountryCode ?? '';
        _timezone.text = saved.timezoneId ?? '';
      });
      _message('حُفظ اختيار المدينة والدولة.');
    } on Object catch (error) {
      _message('تعذّر حفظ الموقع: $error', isError: true);
    }
  }

  Future<void> _useDeviceLocation() async {
    final service = CurrentPrayerLocationService(
      consent: _PrayerLocationConsent(context),
    );
    setState(() => _busy = true);
    try {
      final location = await service.requestCurrentLocation();
      if (location == null || !mounted) return;
      final next = _preferences.copyWith(
        clearManualLocation: true,
        calculationMethod: _method,
        asrMethod: _asrMethod,
      );
      final saved = await _savePreferences(next);
      if (saved == null) return;
      final userId = ref.read(accountSessionProvider)!.id;
      if (saved.manualCity == null) {
        await ref
            .read(localReminderSchedulingEngineProvider)
            .saveDeviceLocationAndReconcile(userId: userId, location: location);
      } else {
        await ref
            .read(localPrayerScheduleLocationStoreProvider)
            .clearDeviceLocation(userId);
      }
      final effectiveLocation = await ref
          .read(localPrayerScheduleLocationStoreProvider)
          .resolve(userId: userId, preferences: saved);
      if (!mounted) return;
      setState(() {
        _preferences = saved;
        _location = effectiveLocation;
        _method =
            saved.calculationMethod ??
            (effectiveLocation == null
                ? null
                : PrayerCalculationMethod.forLocation(effectiveLocation));
        _calendar = null;
        _city.text = saved.manualCity ?? '';
        _country.text = saved.manualCountry ?? '';
        _countryCode.text = saved.manualCountryCode ?? '';
        _timezone.text = saved.timezoneId ?? '';
      });
      _message(
        saved.manualCity == null
            ? 'حُفظ الموقع على هذا الجهاز فقط.'
            : 'حُفظ اختيار الموقع المتزامن مع الحساب.',
      );
    } on Object catch (error) {
      _message('$error', isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveCalculationSettings() async {
    final next = _preferences.copyWith(
      calculationMethod: _method,
      asrMethod: _asrMethod,
    );
    final saved = await _savePreferences(next);
    if (saved == null) return;
    if (!mounted) return;
    setState(() {
      _preferences = saved;
      _method = saved.calculationMethod;
      _asrMethod = saved.asrMethod;
      _calendar = null;
    });
    _message('حُفظت طريقة الحساب.');
  }

  Future<ReminderPreferences?> _savePreferences(
    ReminderPreferences next,
  ) async {
    final userId = ref.read(accountSessionProvider)?.id;
    if (userId == null) return null;
    setState(() => _busy = true);
    try {
      await ref
          .read(localReminderSchedulingEngineProvider)
          .saveLocalPreferencesAndReconcile(userId: userId, preferences: next);
      final result = await ref
          .read(reminderPreferencesSyncServiceProvider)
          .sync(userId);
      var saved = next;
      if (result.status == ReminderSyncStatus.conflict &&
          result.serverSnapshot != null &&
          mounted) {
        final keepDevice = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('تعارض في إعدادات الموقع'),
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
                child: const Text('الاحتفاظ بهذا الاختيار'),
              ),
            ],
          ),
        );
        if (keepDevice != null && mounted) {
          final resolved = await ref
              .read(reminderPreferencesSyncServiceProvider)
              .resolveConflict(
                userId: userId,
                preferences: keepDevice
                    ? next
                    : result.serverSnapshot!.preferences,
                serverSnapshot: result.serverSnapshot!,
              );
          saved = resolved.preferences;
        } else if (mounted) {
          _message(
            'لم يُحسم التعارض؛ احتُفظ بالتعديل المحلي دون استبداله.',
            isError: true,
          );
        }
      } else if (result.status == ReminderSyncStatus.offline && mounted) {
        _message('حُفظ محلياً; ستتم المزامنة عند عودة الاتصال.');
      }
      return saved;
    } on Object catch (error) {
      if (mounted) {
        _message('تعذّر حفظ الإعدادات أو مزامنتها: $error', isError: true);
      }
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkPrayerData() async {
    final userId = ref.read(accountSessionProvider)?.id;
    if (userId == null || _location == null) {
      _message('اختر مدينة أو موقعاً أولاً.', isError: true);
      return;
    }
    setState(() {
      _busy = true;
      _calendar = null;
      _loadError = null;
    });
    try {
      final calendar = await ref
          .read(prayerTimesServiceProvider)
          .fetchCalendarForInstant(
            location: _location!,
            instant: DateTime.now(),
            calculationMethod:
                _method ?? PrayerCalculationMethod.forLocation(_location!),
            asrMethod: _asrMethod,
          );
      if (mounted) setState(() => _calendar = calendar);
    } on PrayerTimesException catch (error) {
      if (mounted) setState(() => _loadError = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('الموقع ومواقيت الصلاة')),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _loadError != null && _location == null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(AppPalette.spaceLg),
              child: Text('تعذّر قراءة الإعدادات: $_loadError'),
            ),
          )
        : Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(AppPalette.spaceMd),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppPalette.spaceMd),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'اختيار يدوي',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: AppPalette.spaceSm),
                          const Text(
                            'لا يحتاج الاختيار اليدوي إلى إذن الموقع.',
                          ),
                          const SizedBox(height: AppPalette.spaceMd),
                          TextField(
                            controller: _city,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'المدينة',
                              hintText: 'القاهرة',
                            ),
                          ),
                          const SizedBox(height: AppPalette.spaceSm),
                          TextField(
                            controller: _country,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'الدولة',
                              hintText: 'مصر',
                            ),
                          ),
                          const SizedBox(height: AppPalette.spaceSm),
                          TextField(
                            controller: _countryCode,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: 'رمز الدولة (اختياري)',
                              hintText: 'EG',
                            ),
                          ),
                          const SizedBox(height: AppPalette.spaceSm),
                          TextField(
                            controller: _timezone,
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'المنطقة الزمنية IANA (اختياري)',
                              hintText: 'Africa/Cairo',
                            ),
                          ),
                          const SizedBox(height: AppPalette.spaceMd),
                          FilledButton(
                            onPressed: _busy ? null : _saveManualLocation,
                            child: const Text('حفظ المدينة'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppPalette.spaceMd),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.my_location),
                      title: const Text('استخدام الموقع الحالي'),
                      subtitle: const Text(
                        'سيظهر طلب موافقة داخل التطبيق قبل طلب إذن النظام. '
                        'الإحداثيات لا تُرفع إلى Supabase.',
                      ),
                      trailing: _busy
                          ? const CircularProgressIndicator()
                          : const Icon(Icons.chevron_left),
                      onTap: _busy ? null : _useDeviceLocation,
                    ),
                  ),
                  const SizedBox(height: AppPalette.spaceMd),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppPalette.spaceMd),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'طريقة حساب المواقيت',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: AppPalette.spaceSm),
                          DropdownButtonFormField<PrayerCalculationMethod>(
                            initialValue:
                                _method ??
                                (_location == null
                                    ? PrayerCalculationMethod.muslimWorldLeague
                                    : PrayerCalculationMethod.forLocation(
                                        _location!,
                                      )),
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'طريقة الحساب',
                            ),
                            selectedItemBuilder: (context) => [
                              for (final method
                                  in PrayerCalculationMethod.values)
                                Text(
                                  '${method.id} — ${method.label}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                            items: [
                              for (final method
                                  in PrayerCalculationMethod.values)
                                DropdownMenuItem(
                                  value: method,
                                  child: Text(
                                    '${method.id} — ${method.label}',
                                    softWrap: true,
                                  ),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _method = value),
                          ),
                          const SizedBox(height: AppPalette.spaceSm),
                          DropdownButtonFormField<AsrCalculationMethod>(
                            initialValue: _asrMethod,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'حساب العصر',
                            ),
                            selectedItemBuilder: (context) => [
                              for (final method in AsrCalculationMethod.values)
                                Text(
                                  method.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                            items: [
                              for (final method in AsrCalculationMethod.values)
                                DropdownMenuItem(
                                  value: method,
                                  child: Text(method.label, softWrap: true),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _asrMethod = value);
                              }
                            },
                          ),
                          const SizedBox(height: AppPalette.spaceMd),
                          OutlinedButton(
                            onPressed: _busy || _location == null
                                ? null
                                : _saveCalculationSettings,
                            child: const Text('حفظ طريقة الحساب'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppPalette.spaceMd),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: const Text('الموقع المحدد'),
                          subtitle: Text(
                            _location?.label ?? 'لم يتم اختيار موقع',
                          ),
                        ),
                        if (_location != null)
                          ListTile(
                            title: const Text('طريقة الحساب الفعلية'),
                            subtitle: Text(
                              (_method ??
                                      PrayerCalculationMethod.forLocation(
                                        _location!,
                                      ))
                                  .label,
                            ),
                            isThreeLine: true,
                            trailing: Text(
                              '(${(_method ?? PrayerCalculationMethod.forLocation(_location!)).id})',
                            ),
                          ),
                        ListTile(
                          title: const Text('حالة البيانات'),
                          subtitle: Text(
                            _calendar == null
                                ? _loadError == null
                                      ? 'لم يتم التحقق بعد'
                                      : 'غير متاحة: $_loadError'
                                : _calendar!.isFromCache
                                ? 'متاحة من التخزين المحلي دون اتصال'
                                : 'تم التحقق من المواقيت عبر مزود البيانات',
                          ),
                          trailing: IconButton(
                            tooltip: 'التحقق الآن',
                            onPressed: _busy ? null : _checkPrayerData,
                            icon: const Icon(Icons.refresh),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
  );
}

class _PrayerLocationConsent implements PrayerLocationConsent {
  const _PrayerLocationConsent(this.context);

  final BuildContext context;

  @override
  Future<bool> confirmCurrentLocationUse() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استخدام موقع الجهاز'),
        content: const Text(
          'سيُستخدم موقعك التقريبي لحساب مواقيت الصلاة. تبقى الإحداثيات '
          'على هذا الجهاز ولا تُرسل إلى Supabase. يمكنك اختيار المدينة يدوياً '
          'بدلاً من ذلك.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ليس الآن'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('المتابعة'),
          ),
        ],
      ),
    );
    return accepted == true;
  }
}
