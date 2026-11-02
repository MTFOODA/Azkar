import 'dart:convert';

import '../../prayer_times/domain/prayer_time_models.dart';

class ReminderPreferences {
  ReminderPreferences({
    this.manualCity,
    this.manualCountry,
    this.manualCountryCode,
    this.timezoneId,
    this.calculationMethod,
    this.asrMethod = AsrCalculationMethod.standard,
    this.prayerRemindersEnabled = false,
    this.prayerTimeNotificationsEnabled = false,
    this.postPrayerTasbeehEnabled = false,
    this.postPrayerDelayMinutes = 0,
    this.morningAzkarEnabled = false,
    this.morningAzkarTime = '07:00',
    this.eveningAzkarEnabled = false,
    this.eveningAzkarTime = '18:00',
    this.fridayKahfEnabled = false,
    this.fridayKahfTime = '09:00',
    this.quietHoursStart,
    this.quietHoursEnd,
    this.hideNotificationContent = false,
    List<ReminderConfiguration> configurations =
        const <ReminderConfiguration>[],
  }) : configurations = List<ReminderConfiguration>.unmodifiable(
         configurations,
       ) {
    if ((manualCity == null) != (manualCountry == null)) {
      throw ArgumentError('Manual city and country must be set together.');
    }
    if (manualCity != null &&
        (manualCity!.trim().isEmpty ||
            manualCity!.trim().length > 160 ||
            manualCountry!.trim().isEmpty ||
            manualCountry!.trim().length > 160)) {
      throw ArgumentError(
        'Manual city and country must be between 1 and 160 characters.',
      );
    }
    if (manualCity == null && manualCountryCode != null) {
      throw ArgumentError('A country code requires a manually selected city.');
    }
    if (manualCountryCode != null &&
        !RegExp(r'^[A-Za-z]{2}$').hasMatch(manualCountryCode!.trim())) {
      throw ArgumentError.value(manualCountryCode, 'manualCountryCode');
    }
    if (timezoneId != null &&
        (timezoneId!.trim().isEmpty || timezoneId!.trim().length > 100)) {
      throw ArgumentError.value(timezoneId, 'timezoneId');
    }
    _validateClockTime(morningAzkarTime, 'morningAzkarTime');
    _validateClockTime(eveningAzkarTime, 'eveningAzkarTime');
    _validateClockTime(fridayKahfTime, 'fridayKahfTime');
    if ((quietHoursStart == null) != (quietHoursEnd == null)) {
      throw ArgumentError('Both quiet-hours times must be set together.');
    }
    if (quietHoursStart case final start?) {
      _validateClockTime(start, 'quietHoursStart');
      _validateClockTime(quietHoursEnd!, 'quietHoursEnd');
    }
    if (postPrayerDelayMinutes < 0 || postPrayerDelayMinutes > 1440) {
      throw ArgumentError.value(
        postPrayerDelayMinutes,
        'postPrayerDelayMinutes',
      );
    }
    if (configurations.map((item) => item.id).toSet().length !=
        configurations.length) {
      throw ArgumentError('Reminder configuration IDs must be unique.');
    }
    if (configurations.length > 100) {
      throw ArgumentError('At most 100 reminder configurations are allowed.');
    }
  }

  final String? manualCity;
  final String? manualCountry;
  final String? manualCountryCode;
  final String? timezoneId;
  final PrayerCalculationMethod? calculationMethod;
  final AsrCalculationMethod asrMethod;
  final bool prayerRemindersEnabled;
  final bool prayerTimeNotificationsEnabled;
  final bool postPrayerTasbeehEnabled;
  final int postPrayerDelayMinutes;
  final bool morningAzkarEnabled;
  final String morningAzkarTime;
  final bool eveningAzkarEnabled;
  final String eveningAzkarTime;
  final bool fridayKahfEnabled;
  final String fridayKahfTime;
  final String? quietHoursStart;
  final String? quietHoursEnd;
  final bool hideNotificationContent;
  final List<ReminderConfiguration> configurations;

  ReminderPreferences copyWith({
    String? manualCity,
    String? manualCountry,
    String? manualCountryCode,
    bool clearManualCountryCode = false,
    String? timezoneId,
    bool clearTimezoneId = false,
    bool clearManualLocation = false,
    PrayerCalculationMethod? calculationMethod,
    AsrCalculationMethod? asrMethod,
    bool? prayerRemindersEnabled,
    bool? prayerTimeNotificationsEnabled,
    bool? postPrayerTasbeehEnabled,
    int? postPrayerDelayMinutes,
    bool? morningAzkarEnabled,
    String? morningAzkarTime,
    bool? eveningAzkarEnabled,
    String? eveningAzkarTime,
    bool? fridayKahfEnabled,
    String? fridayKahfTime,
    String? quietHoursStart,
    String? quietHoursEnd,
    bool clearQuietHours = false,
    bool? hideNotificationContent,
    List<ReminderConfiguration>? configurations,
  }) => ReminderPreferences(
    manualCity: clearManualLocation ? null : manualCity ?? this.manualCity,
    manualCountry: clearManualLocation
        ? null
        : manualCountry ?? this.manualCountry,
    manualCountryCode: clearManualLocation
        ? null
        : clearManualCountryCode
        ? null
        : manualCountryCode ?? this.manualCountryCode,
    timezoneId: clearManualLocation || clearTimezoneId
        ? null
        : timezoneId ?? this.timezoneId,
    calculationMethod: calculationMethod ?? this.calculationMethod,
    asrMethod: asrMethod ?? this.asrMethod,
    prayerRemindersEnabled:
        prayerRemindersEnabled ?? this.prayerRemindersEnabled,
    prayerTimeNotificationsEnabled:
        prayerTimeNotificationsEnabled ?? this.prayerTimeNotificationsEnabled,
    postPrayerTasbeehEnabled:
        postPrayerTasbeehEnabled ?? this.postPrayerTasbeehEnabled,
    postPrayerDelayMinutes:
        postPrayerDelayMinutes ?? this.postPrayerDelayMinutes,
    morningAzkarEnabled: morningAzkarEnabled ?? this.morningAzkarEnabled,
    morningAzkarTime: morningAzkarTime ?? this.morningAzkarTime,
    eveningAzkarEnabled: eveningAzkarEnabled ?? this.eveningAzkarEnabled,
    eveningAzkarTime: eveningAzkarTime ?? this.eveningAzkarTime,
    fridayKahfEnabled: fridayKahfEnabled ?? this.fridayKahfEnabled,
    fridayKahfTime: fridayKahfTime ?? this.fridayKahfTime,
    quietHoursStart: clearQuietHours
        ? null
        : quietHoursStart ?? this.quietHoursStart,
    quietHoursEnd: clearQuietHours ? null : quietHoursEnd ?? this.quietHoursEnd,
    hideNotificationContent:
        hideNotificationContent ?? this.hideNotificationContent,
    configurations: configurations ?? this.configurations,
  );

  static final defaults = ReminderPreferences();

  Map<String, Object?> toJson() => <String, Object?>{
    'manual_city': manualCity?.trim(),
    'manual_country': manualCountry?.trim(),
    'manual_country_code': manualCountryCode?.trim().toUpperCase(),
    'timezone_id': timezoneId,
    'calculation_method': calculationMethod?.id,
    'asr_method': asrMethod.id,
    'prayer_reminders_enabled': prayerRemindersEnabled,
    'prayer_time_notifications_enabled': prayerTimeNotificationsEnabled,
    'post_prayer_tasbeeh_enabled': postPrayerTasbeehEnabled,
    'post_prayer_delay_minutes': postPrayerDelayMinutes,
    'morning_azkar_enabled': morningAzkarEnabled,
    'morning_azkar_time': morningAzkarTime,
    'evening_azkar_enabled': eveningAzkarEnabled,
    'evening_azkar_time': eveningAzkarTime,
    'friday_kahf_enabled': fridayKahfEnabled,
    'friday_kahf_time': fridayKahfTime,
    'quiet_hours_start': quietHoursStart,
    'quiet_hours_end': quietHoursEnd,
    'hide_notification_content': hideNotificationContent,
    'configurations': configurationsJson,
  };

  Map<String, Object?> toSettingsJson() {
    final json = toJson()
      ..remove('manual_city')
      ..remove('manual_country')
      ..remove('manual_country_code')
      ..remove('timezone_id')
      ..remove('configurations');
    return json;
  }

  List<Map<String, Object?>> get configurationsJson {
    final serialized = configurations
        .map((configuration) => configuration.toJson())
        .toList();
    serialized.sort(
      (left, right) => '${left['id']}'.compareTo('${right['id']}'),
    );
    return serialized;
  }

  String get canonicalJson => _canonicalJsonEncode(toJson());

  bool hasSameValues(ReminderPreferences other) =>
      canonicalJson == other.canonicalJson;

  bool hasSameSyncedValues(ReminderPreferences other) =>
      _canonicalJsonEncode(_toSyncedJson()) ==
      _canonicalJsonEncode(other._toSyncedJson());

  Map<String, Object?> _toSyncedJson() => <String, Object?>{
    'manual_city': manualCity?.trim(),
    'manual_country': manualCountry?.trim(),
    'manual_country_code': manualCountryCode?.trim().toUpperCase(),
    'timezone_id': manualCity == null ? null : timezoneId,
    'settings': toSettingsJson(),
    'configurations': configurationsJson,
  };

  factory ReminderPreferences.fromJson(Map<String, dynamic> json) {
    final rawConfigurations = json['configurations'];
    if (rawConfigurations != null &&
        (rawConfigurations is! List ||
            rawConfigurations.any((value) => value is! Map))) {
      throw const FormatException('Invalid reminder configurations.');
    }
    final rawMethod = json['calculation_method'];
    final methodId = rawMethod == null ? null : _readInt(rawMethod);
    final countryCode = _readNullableString(json['manual_country_code']);
    return ReminderPreferences(
      manualCity: _readNullableString(json['manual_city']),
      manualCountry: _readNullableString(json['manual_country']),
      manualCountryCode: countryCode?.toUpperCase(),
      timezoneId: _readNullableString(json['timezone_id']),
      calculationMethod: methodId == null
          ? null
          : PrayerCalculationMethod.fromId(methodId),
      asrMethod: AsrCalculationMethod.fromId(_readInt(json['asr_method']) ?? 0),
      prayerRemindersEnabled: _readBool(json['prayer_reminders_enabled']),
      prayerTimeNotificationsEnabled: _readBool(
        json['prayer_time_notifications_enabled'],
      ),
      postPrayerTasbeehEnabled: _readBool(json['post_prayer_tasbeeh_enabled']),
      postPrayerDelayMinutes: _readInt(json['post_prayer_delay_minutes']) ?? 0,
      morningAzkarEnabled: _readBool(json['morning_azkar_enabled']),
      morningAzkarTime: _readString(json['morning_azkar_time'], '07:00'),
      eveningAzkarEnabled: _readBool(json['evening_azkar_enabled']),
      eveningAzkarTime: _readString(json['evening_azkar_time'], '18:00'),
      fridayKahfEnabled: _readBool(json['friday_kahf_enabled']),
      fridayKahfTime: _readString(json['friday_kahf_time'], '09:00'),
      quietHoursStart: _readNullableString(json['quiet_hours_start']),
      quietHoursEnd: _readNullableString(json['quiet_hours_end']),
      hideNotificationContent: _readBool(json['hide_notification_content']),
      configurations: rawConfigurations == null
          ? const <ReminderConfiguration>[]
          : rawConfigurations
                .map<ReminderConfiguration>(
                  (value) => ReminderConfiguration.fromJson(
                    Map<String, dynamic>.from(value as Map),
                  ),
                )
                .toList(growable: false),
    );
  }

  factory ReminderPreferences.fromRemoteRow(Map<String, dynamic> row) {
    final settings = row['settings'];
    final configurations = row['configurations'] ?? const <Object?>[];
    if (settings is! Map ||
        configurations is! List ||
        configurations.any((value) => value is! Map)) {
      throw const FormatException('Invalid remote reminder preferences.');
    }
    return ReminderPreferences.fromJson(<String, dynamic>{
      ...Map<String, dynamic>.from(settings),
      'manual_city': row['manual_city'],
      'manual_country': row['manual_country'],
      'manual_country_code': row['manual_country_code'],
      'timezone_id': row['timezone_id'],
      'configurations': configurations,
    });
  }

  static String? _readNullableString(Object? value) {
    if (value == null) return null;
    if (value is! String) throw const FormatException('Invalid text value.');
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _readString(Object? value, String fallback) {
    if (value == null) return fallback;
    if (value is! String) throw const FormatException('Invalid text value.');
    _validateClockTime(value, 'time');
    return value;
  }

  static int? _readInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.roundToDouble()) {
      return value.toInt();
    }
    throw const FormatException('Invalid integer value.');
  }

  static bool _readBool(Object? value, {bool fallback = false}) {
    if (value == null) return fallback;
    if (value is bool) return value;
    throw const FormatException('Invalid boolean value.');
  }

  static void _validateClockTime(String value, String name) {
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value);
    if (match == null) throw ArgumentError.value(value, name);
  }
}

class ReminderConfiguration {
  ReminderConfiguration({
    required this.id,
    required this.kind,
    required this.enabled,
    required Map<String, Object?> parameters,
    this.memorialPageId,
  }) : parameters = _freezeJsonMap(parameters) {
    if (id.trim().isEmpty ||
        id.trim().length > 100 ||
        kind.trim().isEmpty ||
        kind.trim().length > 80) {
      throw ArgumentError(
        'Reminder configuration ID and kind have invalid lengths.',
      );
    }
    if (reminderJsonContainsCoordinates(parameters)) {
      throw ArgumentError('GPS coordinates cannot be reminder configuration.');
    }
    if (memorialPageId != null && memorialPageId!.trim().isEmpty) {
      throw ArgumentError.value(memorialPageId, 'memorialPageId');
    }
  }

  final String id;
  final String kind;
  final bool enabled;
  final Map<String, Object?> parameters;
  final String? memorialPageId;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'kind': kind,
    'enabled': enabled,
    'parameters': parameters,
    'memorial_page_id': memorialPageId,
  };

  factory ReminderConfiguration.fromJson(Map<String, dynamic> json) {
    final parameters = json['parameters'];
    final enabled = json['enabled'];
    if (parameters != null && parameters is! Map) {
      throw const FormatException('Invalid reminder parameters.');
    }
    if (enabled is! bool) {
      throw const FormatException('Invalid reminder enabled state.');
    }
    return ReminderConfiguration(
      id: _requiredString(json['id']),
      kind: _requiredString(json['kind']),
      enabled: enabled,
      parameters: parameters == null
          ? const <String, Object?>{}
          : Map<String, Object?>.from(parameters as Map),
      memorialPageId: ReminderPreferences._readNullableString(
        json['memorial_page_id'],
      ),
    );
  }

  static String _requiredString(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      throw const FormatException(
        'Required reminder configuration text is missing.',
      );
    }
    return value;
  }

  static bool _isCoordinateKey(String key) {
    final normalized = key.trim().toLowerCase();
    return normalized == 'latitude' ||
        normalized == 'longitude' ||
        normalized == 'lat' ||
        normalized == 'lng' ||
        normalized == 'coordinates' ||
        normalized == 'gps' ||
        normalized == 'location';
  }
}

class ReminderPreferencesSnapshot {
  const ReminderPreferencesSnapshot({
    required this.preferences,
    required this.revision,
    required this.updatedAt,
  });

  final ReminderPreferences preferences;
  final int revision;
  final DateTime updatedAt;
}

class LocalReminderPreferencesState {
  const LocalReminderPreferencesState({
    required this.preferences,
    required this.baseRevision,
    required this.isDirty,
    this.serverSnapshot,
  });

  final ReminderPreferences preferences;
  final int baseRevision;
  final bool isDirty;
  final ReminderPreferencesSnapshot? serverSnapshot;
}

enum ReminderSyncStatus { synchronized, offline, conflict }

class ReminderSyncResult {
  const ReminderSyncResult({
    required this.status,
    required this.preferences,
    this.serverSnapshot,
  });

  final ReminderSyncStatus status;
  final ReminderPreferences preferences;
  final ReminderPreferencesSnapshot? serverSnapshot;
}

bool reminderJsonContainsCoordinates(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      if (ReminderConfiguration._isCoordinateKey('${entry.key}') ||
          reminderJsonContainsCoordinates(entry.value)) {
        return true;
      }
    }
  }
  if (value is List) {
    return value.any(reminderJsonContainsCoordinates);
  }
  return false;
}

Map<String, Object?> _freezeJsonMap(Map<String, Object?> value) =>
    Map<String, Object?>.unmodifiable(
      value.map((key, item) => MapEntry(key, _freezeJsonValue(item))),
    );

Object? _freezeJsonValue(Object? value) {
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(
      value.map((key, item) => MapEntry('$key', _freezeJsonValue(item))),
    );
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_freezeJsonValue));
  }
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  throw ArgumentError.value(value, 'parameters', 'Must contain JSON values.');
}

String _canonicalJsonEncode(Object? value) => jsonEncode(_canonicalize(value));

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((key) => '$key').toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  if (value is List) return value.map(_canonicalize).toList(growable: false);
  return value;
}
