import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../../../core/design/app_palette.dart';
import '../../../core/providers/app_providers.dart';
import '../../prayer_times/domain/prayer_time_errors.dart';
import '../../prayer_times/domain/prayer_time_models.dart';
import '../../prayer_tracking/domain/prayer_completion_state_machine.dart';
import '../../reminders/domain/reminder_preferences.dart';

class PrayerDashboardPage extends ConsumerStatefulWidget {
  const PrayerDashboardPage({super.key});

  @override
  ConsumerState<PrayerDashboardPage> createState() =>
      _PrayerDashboardPageState();
}

class _PrayerDashboardPageState extends ConsumerState<PrayerDashboardPage> {
  _PrayerDashboardData? _data;
  Object? _error;
  bool _loading = true;
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted) return;
      final data = _data;
      if (data != null) {
        final localNow = timezone.TZDateTime.from(
          DateTime.now(),
          PrayerTimeZones.location(data.timezoneId),
        );
        final prayerDate = data.today.localDate;
        if (localNow.year != prayerDate.year ||
            localNow.month != prayerDate.month ||
            localNow.day != prayerDate.day) {
          unawaited(_load());
          return;
        }
      }
      final next = _data?.nextPrayer;
      if (next != null && !next.time.isAfter(DateTime.now())) {
        unawaited(_load());
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = ref.read(accountSessionProvider)?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _data = null;
          _loading = false;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      PrayerTimeZones.initialize();
      final preferences =
          (await ref.read(reminderPreferencesLocalStoreProvider).read(userId))
              ?.preferences;
      final settings = preferences ?? ReminderPreferences.defaults;
      final location = await ref
          .read(localPrayerScheduleLocationStoreProvider)
          .resolve(userId: userId, preferences: settings);
      if (location == null) {
        if (mounted) {
          setState(() {
            _data = null;
            _loading = false;
          });
        }
        return;
      }
      final service = ref.read(prayerTimesServiceProvider);
      final now = DateTime.now();
      final todayCalendar = await service.fetchCalendarForInstant(
        location: location,
        instant: now,
        calculationMethod: settings.calculationMethod,
        asrMethod: settings.asrMethod,
      );
      final today = todayCalendar.dayForInstant(now);
      if (today == null) {
        throw const PrayerTimesDataException(
          'لا تتوفر بيانات الصلاة لهذا اليوم.',
        );
      }
      final zone = PrayerTimeZones.location(todayCalendar.timezoneId);
      final localNow = timezone.TZDateTime.from(now, zone);
      final todayUpcoming = _upcomingPrayer(today, localNow);
      var nextPrayer = todayUpcoming;
      var nextCalendar = todayCalendar;
      if (todayUpcoming == null) {
        final tomorrow = timezone.TZDateTime(
          zone,
          localNow.year,
          localNow.month,
          localNow.day + 1,
        );
        nextCalendar = await service.fetchCalendarForInstant(
          location: location,
          instant: tomorrow,
          calculationMethod: settings.calculationMethod,
          asrMethod: settings.asrMethod,
        );
        final nextDay = nextCalendar.dayForInstant(tomorrow) ?? today;
        nextPrayer = _firstPrayer(nextDay);
      }
      final states = await ref
          .read(prayerCompletionStateMachineProvider)
          .statesForDay(userId: userId, prayerDay: today);
      if (!mounted) return;
      setState(() {
        _data = _PrayerDashboardData(
          userId: userId,
          location: location,
          settings: settings,
          today: today,
          states: states,
          timezoneId: todayCalendar.timezoneId,
          isCached: todayCalendar.isFromCache || nextCalendar.isFromCache,
          nextPrayer: nextPrayer,
        );
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  _PrayerTime? _upcomingPrayer(PrayerDay day, timezone.TZDateTime now) {
    for (final prayer in TrackedPrayer.values) {
      final name = prayer.prayerTimeName;
      final time = day.timeFor(name);
      if (time.isAfter(now)) return _PrayerTime(prayer: prayer, time: time);
    }
    return null;
  }

  _PrayerTime? _firstPrayer(PrayerDay day) {
    if (TrackedPrayer.values.isEmpty) return null;
    final prayer = TrackedPrayer.values.first;
    return _PrayerTime(
      prayer: prayer,
      time: day.timeFor(prayer.prayerTimeName),
    );
  }

  Future<void> _complete(
    _PrayerDashboardData data,
    TrackedPrayer prayer,
  ) async {
    final prayerTime = data.today.timeFor(prayer.prayerTimeName);
    try {
      await ref
          .read(prayerCompletionStateMachineProvider)
          .setManuallyCompleted(
            userId: data.userId,
            prayer: prayer,
            prayerTime: prayerTime,
            completed: true,
          );
      await ref
          .read(tasbeehOutboxCoordinatorProvider)
          .reconcilePending(data.userId);
      await _load();
    } on Object catch (error) {
      _showMessage('تعذّر تحديث حالة الصلاة: $error');
    }
  }

  Future<void> _correct(_PrayerDashboardData data, TrackedPrayer prayer) async {
    try {
      await ref
          .read(prayerCompletionStateMachineProvider)
          .setManuallyCompleted(
            userId: data.userId,
            prayer: prayer,
            prayerTime: data.today.timeFor(prayer.prayerTimeName),
            completed: false,
          );
      await _load();
    } on Object catch (error) {
      _showMessage('تعذّر تصحيح حالة الصلاة: $error');
    }
  }

  Future<void> _markNotYetPrayed(
    _PrayerDashboardData data,
    PrayerCompletionState state,
  ) async {
    try {
      await ref
          .read(prayerCompletionStateMachineProvider)
          .handleAction(
            userId: data.userId,
            occurrenceId: state.identity.id,
            action: PrayerCompletionAction.notYetPrayed,
          );
      await _load();
    } on Object catch (error) {
      _showMessage('تعذّر تحديث التذكير: $error');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مواقيت الصلاة'),
        actions: [
          IconButton(
            tooltip: 'إعدادات التذكير',
            onPressed: () => context.push('/worship/reminders'),
            icon: const Icon(Icons.notifications_outlined),
          ),
          IconButton(
            tooltip: 'إعدادات الموقع',
            onPressed: () => context.push('/worship/location'),
            icon: const Icon(Icons.location_on_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'جارٍ تحميل مواقيت الصلاة',
                    ),
                  )
                : _error != null
                ? _ErrorState(error: _error!, onRetry: _load)
                : _data == null
                ? _NoLocationState(
                    onSelect: () => context.push('/worship/location'),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(AppPalette.spaceMd),
                      children: [
                        _DateCard(data: _data!),
                        const SizedBox(height: AppPalette.spaceMd),
                        _NextPrayerCard(
                          prayer: _data!.nextPrayer,
                          timezoneId: _data!.timezoneId,
                        ),
                        const SizedBox(height: AppPalette.spaceMd),
                        for (final state in _data!.states) ...[
                          _PrayerRow(
                            state: state,
                            time: _data!.today.timeFor(
                              state.identity.prayer.prayerTimeName,
                            ),
                            isNext:
                                _data!.nextPrayer?.prayer ==
                                    state.identity.prayer &&
                                _data!.nextPrayer!.time ==
                                    _data!.today.timeFor(
                                      state.identity.prayer.prayerTimeName,
                                    ),
                            onComplete: () =>
                                _complete(_data!, state.identity.prayer),
                            onCorrect: () =>
                                _correct(_data!, state.identity.prayer),
                            onNotYetPrayed: () =>
                                _markNotYetPrayed(_data!, state),
                          ),
                          const SizedBox(height: AppPalette.spaceSm),
                        ],
                        Card(
                          child: ListTile(
                            leading: Icon(
                              _data!.isCached
                                  ? Icons.cloud_off_outlined
                                  : Icons.cloud_done_outlined,
                            ),
                            title: Text(
                              _data!.isCached
                                  ? 'مواقيت محفوظة للاستخدام دون اتصال'
                                  : 'بيانات المواقيت محدثة',
                            ),
                            subtitle: Text(
                              'المنطقة الزمنية: ${_data!.timezoneId}',
                            ),
                          ),
                        ),
                        const SizedBox(height: AppPalette.spaceMd),
                        FilledButton.icon(
                          onPressed: () => context.push('/worship/reminders'),
                          icon: const Icon(Icons.tune),
                          label: const Text('إعدادات الصلاة والتذكير'),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _PrayerDashboardData {
  const _PrayerDashboardData({
    required this.userId,
    required this.location,
    required this.settings,
    required this.today,
    required this.states,
    required this.timezoneId,
    required this.isCached,
    required this.nextPrayer,
  });

  final String userId;
  final PrayerLocation location;
  final ReminderPreferences settings;
  final PrayerDay today;
  final List<PrayerCompletionState> states;
  final String timezoneId;
  final bool isCached;
  final _PrayerTime? nextPrayer;
}

class _PrayerTime {
  const _PrayerTime({required this.prayer, required this.time});

  final TrackedPrayer prayer;
  final timezone.TZDateTime time;
}

class _DateCard extends StatelessWidget {
  const _DateCard({required this.data});

  final _PrayerDashboardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final date = DateFormat.yMMMMEEEEd('ar').format(data.today.localDate);
    return Card(
      color: theme.colorScheme.primary,
      child: Padding(
        padding: const EdgeInsets.all(AppPalette.spaceLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              date,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onPrimary,
              ),
            ),
            const SizedBox(height: AppPalette.spaceSm),
            Text(
              data.location.label,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppPalette.spaceXs),
            Text(
              'حساب ${data.settings.calculationMethod?.label ?? PrayerCalculationMethod.forLocation(data.location).label}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextPrayerCard extends StatelessWidget {
  const _NextPrayerCard({required this.prayer, required this.timezoneId});

  final _PrayerTime? prayer;
  final String timezoneId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (prayer == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(AppPalette.spaceMd),
          child: Text('تعذّر تحديد الصلاة القادمة.'),
        ),
      );
    }
    final now = timezone.TZDateTime.from(
      DateTime.now(),
      PrayerTimeZones.location(timezoneId),
    );
    final remaining = prayer!.time.difference(now);
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes.remainder(60);
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.schedule,
          color: theme.colorScheme.secondary,
          size: 32,
        ),
        title: Text(
          'الصلاة القادمة: ${_prayerArabic(prayer!.prayer)}',
          style: theme.textTheme.titleMedium,
        ),
        subtitle: Text(
          '${DateFormat.Hm('ar').format(prayer!.time)} • متبقي '
          '${hours > 0 ? '$hours س و' : ''}$minutes د',
        ),
      ),
    );
  }
}

class _PrayerRow extends StatelessWidget {
  const _PrayerRow({
    required this.state,
    required this.time,
    required this.isNext,
    required this.onComplete,
    required this.onCorrect,
    required this.onNotYetPrayed,
  });

  final PrayerCompletionState state;
  final timezone.TZDateTime time;
  final bool isNext;
  final VoidCallback onComplete;
  final VoidCallback onCorrect;
  final VoidCallback onNotYetPrayed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prayer = state.identity.prayer;
    final completed = state.status == PrayerCompletionStatus.completed;
    return Card(
      color: isNext
          ? theme.colorScheme.secondary.withValues(alpha: 0.13)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppPalette.spaceMd,
          vertical: AppPalette.spaceSm,
        ),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                completed ? Icons.check_circle : Icons.radio_button_unchecked,
                color: completed ? theme.colorScheme.primary : null,
              ),
              title: Text(
                _prayerArabic(prayer),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text(DateFormat.Hm('ar').format(time)),
              trailing: Text(
                _statusArabic(state.status),
                style: theme.textTheme.labelMedium,
              ),
            ),
            if (completed)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: onCorrect,
                  child: const Text('تصحيح: لم أصلِّ'),
                ),
              )
            else
              Wrap(
                spacing: AppPalette.spaceSm,
                runSpacing: AppPalette.spaceXs,
                alignment: WrapAlignment.start,
                children: [
                  OutlinedButton.icon(
                    onPressed: onComplete,
                    icon: const Icon(Icons.check),
                    label: const Text('صليت'),
                  ),
                  if (state.status == PrayerCompletionStatus.reminderSent &&
                      state.scheduledReminderCount == 1)
                    TextButton(
                      onPressed: onNotYetPrayed,
                      child: const Text('لسه مصليتش'),
                    ),
                ],
              ),
            if (completed)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FilledButton.tonalIcon(
                  onPressed: () => context.go('/worship/tasbeeh'),
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('ابدأ التسبيح بعد الصلاة'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoLocationState extends StatelessWidget {
  const _NoLocationState({required this.onSelect});

  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppPalette.spaceXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_searching, size: 48),
          const SizedBox(height: AppPalette.spaceMd),
          const Text(
            'اختر مدينتك لعرض مواقيت الصلاة.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppPalette.spaceMd),
          FilledButton(onPressed: onSelect, child: const Text('إعداد الموقع')),
        ],
      ),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppPalette.spaceXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: AppPalette.spaceMd),
          Text(
            'تعذّر تحميل مواقيت الصلاة.\n$error',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppPalette.spaceMd),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    ),
  );
}

String _prayerArabic(TrackedPrayer prayer) => switch (prayer) {
  TrackedPrayer.fajr => 'الفجر',
  TrackedPrayer.dhuhr => 'الظهر',
  TrackedPrayer.asr => 'العصر',
  TrackedPrayer.maghrib => 'المغرب',
  TrackedPrayer.isha => 'العشاء',
};

String _statusArabic(PrayerCompletionStatus status) => switch (status) {
  PrayerCompletionStatus.notConfirmed => 'لم يُسجّل بعد',
  PrayerCompletionStatus.reminderSent => 'أُرسل تذكير',
  PrayerCompletionStatus.notYetPrayed => 'لم أصلِّ بعد',
  PrayerCompletionStatus.completed => 'تمت الصلاة',
};
