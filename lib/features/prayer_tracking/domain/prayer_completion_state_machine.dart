import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:timezone/timezone.dart' as timezone;

import '../../prayer_times/domain/prayer_time_models.dart';

enum TrackedPrayer { fajr, dhuhr, asr, maghrib, isha }

extension TrackedPrayerX on TrackedPrayer {
  String get id => name;

  PrayerName get prayerTimeName => switch (this) {
    TrackedPrayer.fajr => PrayerName.fajr,
    TrackedPrayer.dhuhr => PrayerName.dhuhr,
    TrackedPrayer.asr => PrayerName.asr,
    TrackedPrayer.maghrib => PrayerName.maghrib,
    TrackedPrayer.isha => PrayerName.isha,
  };

  static TrackedPrayer? fromId(String id) {
    for (final prayer in TrackedPrayer.values) {
      if (prayer.id == id) return prayer;
    }
    return null;
  }
}

enum PrayerCompletionStatus {
  notConfirmed,
  reminderSent,
  notYetPrayed,
  completed,
}

enum PrayerCompletionAction { prayed, notYetPrayed }

class PrayerOccurrenceIdentity {
  factory PrayerOccurrenceIdentity({
    required String userId,
    required DateTime localDate,
    required TrackedPrayer prayer,
    required String timezoneId,
    required int timezoneOffsetMinutes,
  }) {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty || timezoneId.trim().isEmpty) {
      throw ArgumentError('An account and IANA time zone are required.');
    }
    final timezoneLocation = PrayerTimeZones.location(timezoneId.trim());
    if (timezoneOffsetMinutes.abs() > 14 * 60) {
      throw ArgumentError.value(timezoneOffsetMinutes, 'timezoneOffsetMinutes');
    }
    return PrayerOccurrenceIdentity._(
      userId: normalizedUserId,
      localDate: DateTime.utc(localDate.year, localDate.month, localDate.day),
      prayer: prayer,
      timezoneId: timezoneLocation.name,
      timezoneOffsetMinutes: timezoneOffsetMinutes,
    );
  }

  factory PrayerOccurrenceIdentity.forPrayerTime({
    required String userId,
    required TrackedPrayer prayer,
    required timezone.TZDateTime prayerTime,
  }) => PrayerOccurrenceIdentity(
    userId: userId,
    localDate: prayerTime,
    prayer: prayer,
    timezoneId: prayerTime.location.name,
    timezoneOffsetMinutes: prayerTime.timeZoneOffset.inMinutes,
  );

  const PrayerOccurrenceIdentity._({
    required this.userId,
    required this.localDate,
    required this.prayer,
    required this.timezoneId,
    required this.timezoneOffsetMinutes,
  });

  final String userId;
  final DateTime localDate;
  final TrackedPrayer prayer;
  final String timezoneId;
  final int timezoneOffsetMinutes;

  String get dateKey =>
      '${localDate.year.toString().padLeft(4, '0')}-'
      '${localDate.month.toString().padLeft(2, '0')}-'
      '${localDate.day.toString().padLeft(2, '0')}';

  String get id => sha256
      .convert(
        utf8.encode(
          '$userId|$dateKey|${prayer.id}|$timezoneId|$timezoneOffsetMinutes',
        ),
      )
      .toString();

  bool hasSameOccurrence(PrayerOccurrenceIdentity other) =>
      userId == other.userId &&
      dateKey == other.dateKey &&
      prayer == other.prayer &&
      timezoneId == other.timezoneId &&
      timezoneOffsetMinutes == other.timezoneOffsetMinutes;

  Map<String, Object?> toJson() => <String, Object?>{
    'user_id': userId,
    'local_date': dateKey,
    'prayer': prayer.id,
    'timezone_id': timezoneId,
    'timezone_offset_minutes': timezoneOffsetMinutes,
    'occurrence_id': id,
  };

  factory PrayerOccurrenceIdentity.fromJson(Map<String, dynamic> json) {
    final userId = json['user_id'];
    final date = json['local_date'];
    final prayerId = json['prayer'];
    final timezoneId = json['timezone_id'];
    final offset = json['timezone_offset_minutes'];
    if (userId is! String ||
        date is! String ||
        prayerId is! String ||
        timezoneId is! String ||
        offset is! int) {
      throw const FormatException('Invalid prayer occurrence identity.');
    }
    final parsedDate = DateTime.tryParse(date);
    final prayer = TrackedPrayerX.fromId(prayerId);
    if (parsedDate == null ||
        '${parsedDate.year.toString().padLeft(4, '0')}-'
                '${parsedDate.month.toString().padLeft(2, '0')}-'
                '${parsedDate.day.toString().padLeft(2, '0')}' !=
            date ||
        prayer == null) {
      throw const FormatException('Invalid prayer occurrence identity.');
    }
    final identity = PrayerOccurrenceIdentity(
      userId: userId,
      localDate: parsedDate,
      prayer: prayer,
      timezoneId: timezoneId,
      timezoneOffsetMinutes: offset,
    );
    if (json['occurrence_id'] != identity.id) {
      throw const FormatException(
        'Prayer occurrence identity checksum failed.',
      );
    }
    return identity;
  }
}

class PrayerCompletionState {
  PrayerCompletionState({
    required this.identity,
    required this.prayerTimeUtc,
    required this.status,
    required this.scheduledReminderCount,
    this.pendingReminderOrdinal,
    this.completedAt,
    this.tasbeehEventId,
  }) {
    final zonedPrayerTime = timezone.TZDateTime.from(
      prayerTimeUtc,
      PrayerTimeZones.location(identity.timezoneId),
    );
    if (scheduledReminderCount < 0 ||
        scheduledReminderCount > maximumReminderCount ||
        (pendingReminderOrdinal != null &&
            (pendingReminderOrdinal! < 1 ||
                pendingReminderOrdinal! > maximumReminderCount)) ||
        (status == PrayerCompletionStatus.completed) != (completedAt != null) ||
        (tasbeehEventId != null && tasbeehEventId!.trim().isEmpty) ||
        zonedPrayerTime.year != identity.localDate.year ||
        zonedPrayerTime.month != identity.localDate.month ||
        zonedPrayerTime.day != identity.localDate.day ||
        zonedPrayerTime.timeZoneOffset.inMinutes !=
            identity.timezoneOffsetMinutes) {
      throw ArgumentError('Invalid prayer completion state.');
    }
  }

  static const int maximumReminderCount = 2;
  static const Duration firstReminderDelay = Duration(minutes: 10);
  static const Duration finalReminderDelay = Duration(minutes: 20);

  final PrayerOccurrenceIdentity identity;
  final DateTime prayerTimeUtc;
  final PrayerCompletionStatus status;
  final int scheduledReminderCount;
  final int? pendingReminderOrdinal;
  final DateTime? completedAt;
  final String? tasbeehEventId;

  factory PrayerCompletionState.unscheduled({
    required PrayerOccurrenceIdentity identity,
    required timezone.TZDateTime prayerTime,
  }) => PrayerCompletionState(
    identity: identity,
    prayerTimeUtc: prayerTime.toUtc(),
    status: PrayerCompletionStatus.notConfirmed,
    scheduledReminderCount: 0,
  );

  PrayerCompletionState withPendingReminder(int ordinal) =>
      copyWith(pendingReminderOrdinal: ordinal);

  timezone.TZDateTime get prayerTime => timezone.TZDateTime.from(
    prayerTimeUtc,
    PrayerTimeZones.location(identity.timezoneId),
  );

  timezone.TZDateTime reminderTime(int ordinal) {
    if (ordinal < 1 || ordinal > maximumReminderCount) {
      throw ArgumentError.value(ordinal, 'ordinal');
    }
    final delay = ordinal == 1
        ? firstReminderDelay
        : firstReminderDelay + finalReminderDelay;
    return timezone.TZDateTime.from(
      prayerTimeUtc.add(delay),
      PrayerTimeZones.location(identity.timezoneId),
    );
  }

  PrayerCompletionState copyWith({
    DateTime? prayerTimeUtc,
    PrayerCompletionStatus? status,
    int? scheduledReminderCount,
    int? pendingReminderOrdinal,
    bool clearPendingReminder = false,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    String? tasbeehEventId,
  }) => PrayerCompletionState(
    identity: identity,
    prayerTimeUtc: (prayerTimeUtc ?? this.prayerTimeUtc).toUtc(),
    status: status ?? this.status,
    scheduledReminderCount:
        scheduledReminderCount ?? this.scheduledReminderCount,
    pendingReminderOrdinal: clearPendingReminder
        ? null
        : pendingReminderOrdinal ?? this.pendingReminderOrdinal,
    completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
    tasbeehEventId: tasbeehEventId ?? this.tasbeehEventId,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    ...identity.toJson(),
    'prayer_time_utc': prayerTimeUtc.toIso8601String(),
    'status': status.name,
    'scheduled_reminder_count': scheduledReminderCount,
    'pending_reminder_ordinal': pendingReminderOrdinal,
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'tasbeeh_event_id': tasbeehEventId,
  };

  factory PrayerCompletionState.fromJson(Map<String, dynamic> json) {
    final identity = PrayerOccurrenceIdentity.fromJson(json);
    final prayerTimeUtc = DateTime.tryParse('${json['prayer_time_utc'] ?? ''}');
    final statusName = json['status'];
    final count = json['scheduled_reminder_count'];
    final pending = json['pending_reminder_ordinal'];
    final completedAt = json['completed_at'] == null
        ? null
        : DateTime.tryParse('${json['completed_at']}');
    final eventId = json['tasbeeh_event_id'];
    PrayerCompletionStatus? status;
    for (final candidate in PrayerCompletionStatus.values) {
      if (candidate.name == statusName) {
        status = candidate;
        break;
      }
    }
    if (prayerTimeUtc == null ||
        status == null ||
        count is! int ||
        (pending != null && pending is! int) ||
        (json['completed_at'] != null && completedAt == null) ||
        (eventId != null && eventId is! String)) {
      throw const FormatException('Invalid prayer completion state.');
    }
    return PrayerCompletionState(
      identity: identity,
      prayerTimeUtc: prayerTimeUtc.toUtc(),
      status: status,
      scheduledReminderCount: count,
      pendingReminderOrdinal: pending as int?,
      completedAt: completedAt?.toUtc(),
      tasbeehEventId: eventId as String?,
    );
  }
}

class PrayerCompletionTasbeehEvent {
  const PrayerCompletionTasbeehEvent({
    required this.id,
    required this.userId,
    required this.localDate,
    required this.prayer,
    required this.timezoneId,
    required this.timezoneOffsetMinutes,
    required this.occurredAt,
  });

  final String id;
  final String userId;
  final DateTime localDate;
  final TrackedPrayer prayer;
  final String timezoneId;
  final int timezoneOffsetMinutes;
  final DateTime occurredAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'occurrence_id': occurrenceId,
    'user_id': userId,
    'local_date':
        '${localDate.year.toString().padLeft(4, '0')}-'
        '${localDate.month.toString().padLeft(2, '0')}-'
        '${localDate.day.toString().padLeft(2, '0')}',
    'prayer': prayer.id,
    'timezone_id': timezoneId,
    'timezone_offset_minutes': timezoneOffsetMinutes,
    'occurred_at': occurredAt.toUtc().toIso8601String(),
  };

  String get occurrenceId {
    const suffix = ':post-prayer-tasbeeh';
    if (!id.endsWith(suffix)) {
      throw const FormatException('Invalid post-prayer Tasbeeh event ID.');
    }
    return id.substring(0, id.length - suffix.length);
  }

  factory PrayerCompletionTasbeehEvent.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final occurrenceId = json['occurrence_id'];
    final userId = json['user_id'];
    final date = json['local_date'];
    final prayerId = json['prayer'];
    final timezoneId = json['timezone_id'];
    final timezoneOffset = json['timezone_offset_minutes'];
    final occurredAt = DateTime.tryParse('${json['occurred_at'] ?? ''}');
    final prayer = prayerId is String ? TrackedPrayerX.fromId(prayerId) : null;
    final localDate = date is String ? DateTime.tryParse(date) : null;
    if (id is! String ||
        id.trim().isEmpty ||
        userId is! String ||
        userId.trim().isEmpty ||
        occurrenceId is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(occurrenceId) ||
        date is! String ||
        localDate == null ||
        prayer == null ||
        timezoneId is! String ||
        timezoneOffset is! int ||
        occurredAt == null ||
        id != '$occurrenceId:post-prayer-tasbeeh') {
      throw const FormatException('Invalid post-prayer Tasbeeh event.');
    }
    final identity = PrayerOccurrenceIdentity(
      userId: userId,
      localDate: localDate,
      prayer: prayer,
      timezoneId: timezoneId,
      timezoneOffsetMinutes: timezoneOffset,
    );
    if (identity.id != occurrenceId) {
      throw const FormatException('Tasbeeh event identity checksum failed.');
    }
    return PrayerCompletionTasbeehEvent(
      id: id,
      userId: userId,
      localDate: DateTime.utc(localDate.year, localDate.month, localDate.day),
      prayer: prayer,
      timezoneId: timezoneId,
      timezoneOffsetMinutes: timezoneOffset,
      occurredAt: occurredAt.toUtc(),
    );
  }
}

class PrayerCompletionTransaction {
  const PrayerCompletionTransaction({
    required this.previous,
    required this.current,
  });

  final PrayerCompletionState? previous;
  final PrayerCompletionState current;

  bool get tasbeehEventCreated =>
      previous?.tasbeehEventId == null && current.tasbeehEventId != null;
}

abstract interface class PrayerCompletionStateStore {
  Future<PrayerCompletionState?> readOccurrence({
    required String userId,
    required String occurrenceId,
  });

  Future<List<PrayerCompletionState>> occurrencesForPrayerDate({
    required String userId,
    required DateTime localDate,
    required TrackedPrayer prayer,
  });

  Future<List<PrayerCompletionState>> occurrencesForAccount({
    required String userId,
  });

  Future<List<PrayerCompletionState>> pendingOccurrences({
    required String userId,
  });

  Future<List<PrayerCompletionTasbeehEvent>> pendingTasbeehEvents(
    String userId,
  );

  Future<void> acknowledgeTasbeehEvent({
    required String userId,
    required String eventId,
    required String claimId,
  });

  Future<bool> claimTasbeehEvent({
    required String userId,
    required String eventId,
    required String claimId,
    required DateTime now,
    required Duration leaseDuration,
  });

  Future<void> releaseTasbeehEvent({
    required String userId,
    required String eventId,
    required String claimId,
  });

  Future<PrayerCompletionTransaction> transact({
    required String userId,
    required PrayerOccurrenceIdentity identity,
    required PrayerCompletionState Function(PrayerCompletionState? current)
    transition,
  });
}

abstract interface class PrayerCompletionReminderScheduler {
  Future<void> schedule({
    required String userId,
    required String stableKey,
    required TrackedPrayer prayer,
    required int ordinal,
    required timezone.TZDateTime scheduledAt,
  });

  Future<void> cancel({required String userId, required String stableKey});
}

class PrayerCompletionTransition {
  const PrayerCompletionTransition({required this.state, this.tasbeehEvent});

  final PrayerCompletionState state;
  final PrayerCompletionTasbeehEvent? tasbeehEvent;
}

class PrayerCompletionStateMachine {
  factory PrayerCompletionStateMachine({
    required PrayerCompletionStateStore store,
    required PrayerCompletionReminderScheduler scheduler,
    required String? Function() currentUserIdProvider,
    DateTime Function()? clock,
  }) => PrayerCompletionStateMachine._(
    store,
    scheduler,
    currentUserIdProvider,
    clock ?? DateTime.now,
  );

  PrayerCompletionStateMachine._(
    this._store,
    this._scheduler,
    this._currentUserIdProvider,
    this._clock,
  );

  final PrayerCompletionStateStore _store;
  final PrayerCompletionReminderScheduler _scheduler;
  final String? Function() _currentUserIdProvider;
  final DateTime Function() _clock;
  final StreamController<PrayerCompletionTasbeehEvent> _tasbeehController =
      StreamController<PrayerCompletionTasbeehEvent>.broadcast(sync: true);
  final Set<String> _outboxEventsInFlight = <String>{};
  int _outboxClaimSequence = 0;

  Stream<PrayerCompletionTasbeehEvent> get postPrayerTasbeehEvents =>
      _tasbeehController.stream;
  String stableReminderKey(String occurrenceId, int ordinal) {
    if (occurrenceId.trim().isEmpty ||
        ordinal < 1 ||
        ordinal > PrayerCompletionState.maximumReminderCount) {
      throw ArgumentError('Invalid prayer completion reminder key.');
    }
    return 'prayer-completion:v1:$occurrenceId:reminder:$ordinal';
  }

  Future<PrayerCompletionState> scheduleOccurrence({
    required String userId,
    required TrackedPrayer prayer,
    required timezone.TZDateTime prayerTime,
  }) async {
    _validateUser(userId);
    final identity = PrayerOccurrenceIdentity.forPrayerTime(
      userId: userId,
      prayer: prayer,
      prayerTime: prayerTime,
    );
    final previousOccurrences = await _store.occurrencesForAccount(
      userId: userId,
    );
    for (final previous in previousOccurrences) {
      if (previous.identity.prayer == prayer &&
          !previous.identity.hasSameOccurrence(identity) &&
          (previous.identity.timezoneId != identity.timezoneId ||
              (previous.identity.dateKey == identity.dateKey &&
                  previous.identity.timezoneOffsetMinutes !=
                      identity.timezoneOffsetMinutes))) {
        await _cancelOccurrence(previous);
      }
    }
    await _store.transact(
      userId: userId,
      identity: identity,
      transition: (current) {
        if (current == null) {
          return PrayerCompletionState(
            identity: identity,
            prayerTimeUtc: prayerTime.toUtc(),
            status: PrayerCompletionStatus.notConfirmed,
            scheduledReminderCount: 0,
            pendingReminderOrdinal: 1,
          );
        }
        final updated = current.copyWith(prayerTimeUtc: prayerTime.toUtc());
        if (updated.status == PrayerCompletionStatus.completed) {
          return updated.copyWith(clearPendingReminder: true);
        }
        if (updated.scheduledReminderCount == 0 &&
            updated.pendingReminderOrdinal == null) {
          return updated.copyWith(pendingReminderOrdinal: 1);
        }
        final canRescheduleFirst =
            updated.scheduledReminderCount == 1 &&
            current.reminderTime(1).isAfter(_clock()) &&
            updated.reminderTime(1).isAfter(_clock());
        final canRescheduleFinal =
            updated.scheduledReminderCount == 2 &&
            current.reminderTime(2).isAfter(_clock()) &&
            updated.reminderTime(2).isAfter(_clock());
        if (canRescheduleFirst) {
          return updated.copyWith(pendingReminderOrdinal: 1);
        }
        if (canRescheduleFinal) {
          return updated.copyWith(pendingReminderOrdinal: 2);
        }
        return updated;
      },
    );
    return _reconcile(identity);
  }

  Future<List<PrayerCompletionState>> statesForDay({
    required String userId,
    required PrayerDay prayerDay,
  }) async {
    _validateUser(userId);
    final states = <PrayerCompletionState>[];
    for (final prayer in TrackedPrayer.values) {
      final prayerTime = prayerDay.timeFor(prayer.prayerTimeName);
      final identity = PrayerOccurrenceIdentity.forPrayerTime(
        userId: userId,
        prayer: prayer,
        prayerTime: prayerTime,
      );
      states.add(
        await _store.readOccurrence(
              userId: userId,
              occurrenceId: identity.id,
            ) ??
            PrayerCompletionState.unscheduled(
              identity: identity,
              prayerTime: prayerTime,
            ),
      );
    }
    return List<PrayerCompletionState>.unmodifiable(states);
  }

  Future<PrayerCompletionTransition> setManuallyCompleted({
    required String userId,
    required TrackedPrayer prayer,
    required timezone.TZDateTime prayerTime,
    required bool completed,
  }) async {
    _validateUser(userId);
    final identity = PrayerOccurrenceIdentity.forPrayerTime(
      userId: userId,
      prayer: prayer,
      prayerTime: prayerTime,
    );
    final transaction = await _store.transact(
      userId: userId,
      identity: identity,
      transition: (current) {
        final state =
            current ??
            PrayerCompletionState.unscheduled(
              identity: identity,
              prayerTime: prayerTime,
            );
        if (completed) return _completeState(state);
        if (state.status != PrayerCompletionStatus.completed) return state;
        return state.copyWith(
          status: state.scheduledReminderCount > 0
              ? PrayerCompletionStatus.notYetPrayed
              : PrayerCompletionStatus.notConfirmed,
          clearCompletedAt: true,
          clearPendingReminder: true,
        );
      },
    );
    final event = _tasbeehEvent(transaction);
    if (event != null) _tasbeehController.add(event);
    if (completed) {
      await _cancelOccurrence(transaction.current);
    } else if (transaction.previous?.status ==
            PrayerCompletionStatus.completed &&
        transaction.current.scheduledReminderCount == 0 &&
        transaction.current.reminderTime(1).isAfter(_clock())) {
      await _store.transact(
        userId: userId,
        identity: identity,
        transition: (current) => current!.copyWith(pendingReminderOrdinal: 1),
      );
      await _reconcile(identity);
    }
    final finalState = await _store.readOccurrence(
      userId: userId,
      occurrenceId: identity.id,
    );
    return PrayerCompletionTransition(
      state: finalState ?? transaction.current,
      tasbeehEvent: event,
    );
  }

  Future<PrayerCompletionTransition> handleAction({
    required String userId,
    required String occurrenceId,
    required PrayerCompletionAction action,
  }) async {
    _validateUser(userId);
    final current = await _store.readOccurrence(
      userId: userId,
      occurrenceId: occurrenceId,
    );
    if (current == null) {
      throw StateError('The prayer occurrence is no longer available.');
    }
    if (action == PrayerCompletionAction.prayed) {
      final transaction = await _store.transact(
        userId: userId,
        identity: current.identity,
        transition: (state) => _completeState(state!),
      );
      final event = _tasbeehEvent(transaction);
      if (event != null) _tasbeehController.add(event);
      if (transaction.previous?.status != PrayerCompletionStatus.completed) {
        await _cancelOccurrence(transaction.current);
      }
      return PrayerCompletionTransition(
        state: transaction.current,
        tasbeehEvent: event,
      );
    }

    final transaction = await _store.transact(
      userId: userId,
      identity: current.identity,
      transition: (state) {
        if (state == null || state.status == PrayerCompletionStatus.completed) {
          return state ?? current;
        }
        final canScheduleFinal =
            state.scheduledReminderCount == 1 &&
            state.pendingReminderOrdinal == null &&
            state.reminderTime(2).isAfter(_clock());
        return state.copyWith(
          status: PrayerCompletionStatus.notYetPrayed,
          pendingReminderOrdinal: canScheduleFinal ? 2 : null,
        );
      },
    );
    var state = transaction.current;
    if (state.pendingReminderOrdinal != null) {
      state = await _reconcile(state.identity);
    }
    return PrayerCompletionTransition(state: state);
  }

  Future<void> reconcilePendingSchedules(String userId) async {
    _validateUser(userId);
    final databaseStates = await _store.pendingOccurrences(userId: userId);
    for (final state in databaseStates) {
      if (state.pendingReminderOrdinal != null) {
        await _reconcile(state.identity);
      }
    }
  }

  Future<void> cancelAccountSchedules(String userId) async {
    _validateUser(userId);
    final states = await _store.occurrencesForAccount(userId: userId);
    for (final state in states) {
      await _cancelOccurrence(state);
    }
  }

  Future<void> cancelExpiredSchedules(String userId) async {
    _validateUser(userId);
    final states = await _store.occurrencesForAccount(userId: userId);
    final now = _clock().toUtc();
    for (final state in states) {
      if (!state.reminderTime(2).toUtc().isAfter(now)) {
        await _cancelOccurrence(state);
      }
    }
  }

  Future<void> deliverPendingTasbeehEvents({
    required String userId,
    required Future<void> Function(PrayerCompletionTasbeehEvent event) consumer,
  }) async {
    _validateUser(userId);
    final events = await _store.pendingTasbeehEvents(userId);
    for (final event in events) {
      if (!_outboxEventsInFlight.add(event.id)) continue;
      final claimId =
          '${identityHashCode(this)}:${_clock().microsecondsSinceEpoch}:'
          '${_outboxClaimSequence++}';
      var claimed = false;
      try {
        claimed = await _store.claimTasbeehEvent(
          userId: userId,
          eventId: event.id,
          claimId: claimId,
          now: _clock().toUtc(),
          leaseDuration: const Duration(minutes: 2),
        );
        if (!claimed) continue;
        await consumer(event);
        _validateUser(userId);
        await _store.acknowledgeTasbeehEvent(
          userId: userId,
          eventId: event.id,
          claimId: claimId,
        );
      } catch (_) {
        if (claimed) {
          await _store.releaseTasbeehEvent(
            userId: userId,
            eventId: event.id,
            claimId: claimId,
          );
        }
        rethrow;
      } finally {
        _outboxEventsInFlight.remove(event.id);
      }
    }
  }

  Future<PrayerCompletionState> _reconcile(
    PrayerOccurrenceIdentity identity,
  ) async {
    var state = await _store.readOccurrence(
      userId: identity.userId,
      occurrenceId: identity.id,
    );
    if (state == null) throw StateError('Prayer occurrence was not persisted.');
    final ordinal = state.pendingReminderOrdinal;
    if (ordinal == null || state.status == PrayerCompletionStatus.completed) {
      return state;
    }
    final reminderAt = state.reminderTime(ordinal);
    if (!reminderAt.isAfter(_clock())) {
      final result = await _store.transact(
        userId: identity.userId,
        identity: identity,
        transition: (current) => current!.copyWith(clearPendingReminder: true),
      );
      return result.current;
    }
    await _scheduler.schedule(
      userId: identity.userId,
      stableKey: stableReminderKey(identity.id, ordinal),
      prayer: identity.prayer,
      ordinal: ordinal,
      scheduledAt: reminderAt,
    );
    final result = await _store.transact(
      userId: identity.userId,
      identity: identity,
      transition: (current) {
        if (current == null ||
            current.status == PrayerCompletionStatus.completed ||
            current.pendingReminderOrdinal != ordinal) {
          return current ?? state!;
        }
        return current.copyWith(
          scheduledReminderCount: current.scheduledReminderCount < ordinal
              ? ordinal
              : current.scheduledReminderCount,
          clearPendingReminder: true,
          status:
              ordinal == 1 &&
                  current.status == PrayerCompletionStatus.notConfirmed
              ? PrayerCompletionStatus.reminderSent
              : current.status,
        );
      },
    );
    state = result.current;
    if (state.status == PrayerCompletionStatus.completed) {
      await _cancelOccurrence(state);
    }
    return state;
  }

  PrayerCompletionState _completeState(PrayerCompletionState state) {
    if (state.status == PrayerCompletionStatus.completed) return state;
    final completedAt = _clock().toUtc();
    return state.copyWith(
      status: PrayerCompletionStatus.completed,
      completedAt: completedAt,
      tasbeehEventId:
          state.tasbeehEventId ?? '${state.identity.id}:post-prayer-tasbeeh',
      clearPendingReminder: true,
    );
  }

  PrayerCompletionTasbeehEvent? _tasbeehEvent(
    PrayerCompletionTransaction transaction,
  ) {
    if (!transaction.tasbeehEventCreated) return null;
    final state = transaction.current;
    return PrayerCompletionTasbeehEvent(
      id: state.tasbeehEventId!,
      userId: state.identity.userId,
      localDate: state.identity.localDate,
      prayer: state.identity.prayer,
      timezoneId: state.identity.timezoneId,
      timezoneOffsetMinutes: state.identity.timezoneOffsetMinutes,
      occurredAt: state.completedAt!,
    );
  }

  Future<void> _cancelOccurrence(PrayerCompletionState state) async {
    for (
      var ordinal = 1;
      ordinal <= PrayerCompletionState.maximumReminderCount;
      ordinal++
    ) {
      await _scheduler.cancel(
        userId: state.identity.userId,
        stableKey: stableReminderKey(state.identity.id, ordinal),
      );
    }
  }

  Future<void> dispose() => _tasbeehController.close();

  void _validateUser(String userId) {
    if (userId.trim().isEmpty) throw ArgumentError.value(userId, 'userId');
    if (_currentUserIdProvider()?.trim() != userId) {
      throw StateError('The active account does not own this prayer state.');
    }
  }
}
