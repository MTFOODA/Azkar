import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';

import 'remembrance_widget_preferences.dart';

import '../../content/data/content_repository.dart';
import '../../content/domain/content_item.dart';
import '../../content/domain/content_type.dart';
import '../../memorial/data/memorial_page_repository.dart';
import '../../mobile_platform/domain/mobile_runtime.dart';

class RemembranceWidgetService {
  RemembranceWidgetService({
    required this.runtime,
    required this.currentUserId,
    required this.pageRepository,
    required this.memorialRepository,
    this.preferencesStore,
    this.channel = const MethodChannel('azkar/home_widget'),
  });
  final MobileRuntime runtime;
  final String? Function() currentUserId;
  final ContentRepository Function(String) pageRepository;
  final MemorialPageRepository memorialRepository;
  final MethodChannel channel;
  final RemembranceWidgetPreferencesStore? preferencesStore;
  int _sessionVersion = 0;

  static String accountFingerprint(String userId) =>
      sha256.convert(utf8.encode(userId)).toString().substring(0, 24);

  /// Clear the displayed snapshot immediately when the signed-in account changes.
  Future<void> selectAccount(String? userId) {
    _sessionVersion++;
    if (!runtime.isNativeMobile || currentUserId() != userId) {
      return Future.value();
    }
    return channel.invokeMethod<void>(
      'selectRemembranceAccount',
      userId == null ? null : accountFingerprint(userId),
    );
  }

  bool _isActive(String userId, int version) =>
      currentUserId() == userId && version == _sessionVersion;

  Future<List<Map<String, Object?>>> loadAvailable(String userId) async {
    final version = _sessionVersion;
    if (currentUserId() != userId) return [];
    try {
      return await _collect(userId, version);
    } catch (_) {
      if (!_isActive(userId, version)) return [];
      final cached = await preferencesStore?.readCatalog(userId) ?? [];
      if (!_isActive(userId, version)) return [];
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> _collect(
    String userId,
    int version,
  ) async {
    final cards = <Map<String, Object?>>[];
    Future<void> addContent(
      ContentRepository repository,
      String route, {
      required String pageId,
      String? deceasedName,
      DedicationRecipient? recipient,
    }) async {
      final lists = await Future.wait([
        for (final type in [
          ContentType.azkar,
          ContentType.dua,
          ContentType.dedication,
          ContentType.hadith,
          ContentType.quran,
          ContentType.tasbeeh,
        ])
          repository.fetchPublished(type),
      ]);
      for (final items in lists) {
        for (final item in items.where((item) => item.isPublished)) {
          cards.addAll(
            contentCards(
              item,
              route,
              deceasedName: deceasedName,
              recipient: recipient,
            ).map((card) => {...card, 'ownerUserId': userId, 'pageId': pageId}),
          );
        }
      }
    }

    final pages = await memorialRepository.fetchOwnedPages();
    if (!_isActive(userId, version)) return [];
    for (final page in pages.where(
      (page) => page.isPublished && page.ownerUserId == userId,
    )) {
      if (!_isActive(userId, version)) return [];
      final name = page.deceasedName?.trim() ?? '';
      final recipient = page.deceasedGender == 'female'
          ? DedicationRecipient.female
          : DedicationRecipient.male;
      final route = '/m/${page.slug}';
      if (name.isNotEmpty) {
        cards.add({
          'ownerUserId': userId,
          'pageId': page.id,
          'id': 'memorial:${page.id}',
          'groupId': 'memorial:${page.id}',
          'kind': 'dedication',
          'title': dedicationTitle(name, recipient),
          'dedicationHeading': dedicationHeading(recipient),
          'deceasedName': name,
          'displayName': page.displayDeceasedName,
          'text': page.dedicationMessage?.trim() ?? '',
          'route': route,
        });
      }
      await addContent(
        pageRepository(page.id),
        route,
        pageId: page.id,
        deceasedName: name,
        recipient: recipient,
      );
    }
    if (!_isActive(userId, version)) return [];
    final unique = <String, Map<String, Object?>>{};
    for (final card in cards) {
      unique.putIfAbsent(card['id'] as String, () => card);
    }
    final available = unique.values.toList();
    await preferencesStore?.saveCatalog(userId, available);
    return _isActive(userId, version) ? available : [];
  }

  Future<void> refresh(String userId) async {
    if (!runtime.isNativeMobile || currentUserId() != userId) return;
    final version = _sessionVersion;
    await channel.invokeMethod<void>(
      'selectRemembranceAccount',
      accountFingerprint(userId),
    );
    if (!_isActive(userId, version)) return;
    final available = await loadAvailable(userId);
    if (!_isActive(userId, version)) return;
    final settings =
        await preferencesStore?.read(userId) ??
        const RemembranceWidgetPreferences();
    if (!_isActive(userId, version)) return;
    await channel.invokeMethod<void>(
      'updateRemembrance',
      jsonEncode({
        'version': 2,
        'accountFingerprint': accountFingerprint(userId),
        'rotationSeconds': 7,
        'cards': [
          for (final card in available.where(settings.includes).take(200))
            Map.fromEntries(
              card.entries.where(
                (entry) => entry.key != 'ownerUserId' && entry.key != 'pageId',
              ),
            ),
        ],
      }),
    );
  }

  Future<bool> requestPin() async =>
      runtime.isNativeMobile &&
      (await channel.invokeMethod<bool>('requestPinRemembrance') ?? false);

  static String dedicationHeading(DedicationRecipient recipient) =>
      switch (recipient) {
        DedicationRecipient.male => 'صدقة جارية على روح المغفور له بإذن الله',
        DedicationRecipient.female =>
          'صدقة جارية على روح المغفور لها بإذن الله',
        DedicationRecipient.multiple =>
          'صدقة جارية على أرواح المغفور لهم بإذن الله',
      };

  static String dedicationTitle(String name, DedicationRecipient recipient) =>
      '${dedicationHeading(recipient)}\n"$name"';

  /// Split long passages into readable consecutive pages without rewriting.
  static List<Map<String, Object?>> contentCards(
    ContentItem item,
    String route, {
    String? deceasedName,
    DedicationRecipient? recipient,
  }) {
    final ownName = item.personName?.trim() ?? '';
    final name = ownName.isNotEmpty ? ownName : deceasedName?.trim() ?? '';
    final dedicationRecipient = ownName.isNotEmpty
        ? item.recipient
        : recipient ?? item.recipient;
    final isNamedDedication =
        item.type == ContentType.dedication && name.isNotEmpty;
    final title = isNamedDedication
        ? dedicationTitle(name, dedicationRecipient)
        : item.displayTitle.isEmpty
        ? item.type.labelAr
        : item.displayTitle;
    final text = [
      if (!isNamedDedication && (item.personName ?? '').trim().isNotEmpty)
        '${item.recipient.defaultPrefix} ${item.personName}',
      if ((item.dedicationMessage ?? '').trim().isNotEmpty)
        item.dedicationMessage!,
      item.arabicText,
    ].where((text) => text.trim().isNotEmpty).join('\n\n');
    if (text.isEmpty) return [];
    final chunks = <String>[];
    var remaining = text;
    while (remaining.length > 380) {
      var boundary = remaining.lastIndexOf(' ', 380);
      if (boundary < 200) boundary = 380;
      chunks.add(remaining.substring(0, boundary));
      remaining = remaining.substring(boundary).trimLeft();
    }
    if (remaining.isNotEmpty) chunks.add(remaining);
    return [
      for (var index = 0; index < chunks.length; index++)
        {
          'id': '${item.type.id}:${item.id}:$index',
          'groupId': '${item.type.id}:${item.id}',
          'kind': item.type.id,
          'title':
              '$title${chunks.length > 1 ? ' (${index + 1}/${chunks.length})' : ''}',
          if (isNamedDedication) ...{
            'dedicationHeading': dedicationHeading(dedicationRecipient),
            'deceasedName': name,
            'displayName': name.startsWith('المرحوم')
                ? name
                : '${dedicationRecipient.defaultHonorific} $name',
          },
          'text': chunks[index],
          'route': route,
        },
    ];
  }
}
