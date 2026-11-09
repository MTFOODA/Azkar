import 'dart:convert';

import 'package:flutter/services.dart';

import 'remembrance_widget_preferences.dart';

import '../../content/data/content_repository.dart';
import '../../content/domain/content_item.dart';
import '../../content/domain/content_type.dart';
import '../../memorial/data/memorial_page_repository.dart';
import '../../mobile_platform/domain/mobile_runtime.dart';

class RemembranceWidgetService {
  const RemembranceWidgetService({
    required this.runtime,
    required this.currentUserId,
    required this.globalRepository,
    required this.pageRepository,
    required this.memorialRepository,
    this.preferencesStore,
    this.channel = const MethodChannel('azkar/home_widget'),
  });
  final MobileRuntime runtime;
  final String? Function() currentUserId;
  final ContentRepository globalRepository;
  final ContentRepository Function(String) pageRepository;
  final MemorialPageRepository memorialRepository;
  final MethodChannel channel;
  final RemembranceWidgetPreferencesStore? preferencesStore;

  Future<List<Map<String, Object?>>> loadAvailable(String userId) async {
    if (currentUserId() != userId) return [];
    try {
      return await _collect(userId);
    } catch (_) {
      if (currentUserId() != userId) return [];
      final cached = await preferencesStore?.readCatalog(userId) ?? [];
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<List<Map<String, Object?>>> _collect(String userId) async {
    final cards = <Map<String, Object?>>[];
    Future<void> addContent(
      ContentRepository repository,
      String route, {
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
            ),
          );
        }
      }
    }

    await addContent(globalRepository, '/');
    final pages = await memorialRepository.fetchOwnedPages();
    for (final page
        in pages
            .where((page) => page.isPublished && page.ownerUserId == userId)
            .take(10)) {
      final name = page.deceasedName?.trim() ?? '';
      final recipient = page.deceasedGender == 'female'
          ? DedicationRecipient.female
          : DedicationRecipient.male;
      final route = '/m/${page.slug}';
      if (name.isNotEmpty) {
        cards.add({
          'id': 'memorial:${page.id}',
          'groupId': 'memorial:${page.id}',
          'kind': 'dedication',
          'title': dedicationTitle(name, recipient),
          'dedicationHeading': dedicationHeading(recipient),
          'deceasedName': name,
          'text': page.dedicationMessage?.trim() ?? '',
          'route': route,
        });
      }
      await addContent(
        pageRepository(page.id),
        route,
        deceasedName: name,
        recipient: recipient,
      );
    }
    if (cards.isEmpty) {
      cards.addAll([
        {
          'id': 'default-dhikr',
          'groupId': 'default-dhikr',
          'kind': 'azkar',
          'title': 'ذكر الله',
          'text': 'سبحان الله، والحمد لله، ولا إله إلا الله، والله أكبر.',
          'route': '/azkar',
        },
        {
          'id': 'default-dua',
          'groupId': 'default-dua',
          'kind': 'dua',
          'title': 'دعاء للمتوفّين',
          'text': 'اللهم اغفر لموتانا وموتى المسلمين وارحمهم، واجعل قبورهم روضة من رياض الجنة.',
          'route': '/dua',
        },
      ]);
    }
    if (currentUserId() != userId) return [];
    final unique = <String, Map<String, Object?>>{};
    for (final card in cards) {
      unique.putIfAbsent(card['id'] as String, () => card);
    }
    final available = unique.values.take(200).toList();
    await preferencesStore?.saveCatalog(userId, available);
    return available;
  }

  Future<void> refresh(String userId) async {
    if (!runtime.isNativeMobile || currentUserId() != userId) return;
    final available = await loadAvailable(userId);
    if (currentUserId() != userId) return;
    final settings =
        await preferencesStore?.read(userId) ??
        const RemembranceWidgetPreferences();
    if (currentUserId() != userId) return;
    await channel.invokeMethod<void>(
      'updateRemembrance',
      jsonEncode({
        'version': 1,
        'rotationSeconds': 7,
        'cards': available.where(settings.includes).toList(),
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
          },
          'text': chunks[index],
          'route': route,
        },
    ];
  }
}
