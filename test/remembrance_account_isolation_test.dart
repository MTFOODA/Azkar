import 'dart:async';
import 'dart:convert';

import 'package:azkar/core/storage/local_database.dart';
import 'package:azkar/features/content/data/content_repository.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/features/home_widget/data/remembrance_widget_preferences.dart';
import 'package:azkar/features/home_widget/data/remembrance_widget_service.dart';
import 'package:azkar/features/memorial/data/memorial_page_repository.dart';
import 'package:azkar/features/memorial/domain/memorial_page.dart';
import 'package:azkar/features/mobile_platform/domain/mobile_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('azkar/home_widget');
  late List<MethodCall> calls;
  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  Map<String, dynamic> payload() => Map<String, dynamic>.from(
    jsonDecode(
      calls.lastWhere((call) => call.method == 'updateRemembrance').arguments
          as String,
    ) as Map,
  );

  test('three accounts on one device keep content, filters and offline catalogs separate', () async {
    final db = await openNewInMemoryDatabase();
    addTearDown(db.close);
    var active = 'a';
    final repos = {
      for (final user in ['a', 'b', 'c']) 'page-$user': _Content('page-$user'),
    };
    final store = RemembranceWidgetPreferencesStore(
      databaseProvider: () async => db,
      currentUserId: () => active,
    );
    final service = _service(() => active, repos, store);
    for (final user in ['a', 'b', 'c']) {
      active = user;
      await service.selectAccount(user);
      if (user == 'a') {
        await store.save(
          user,
          const RemembranceWidgetPreferences(hiddenTypes: {'azkar', 'tasbeeh'}),
        );
      }
      await service.refresh(user);
      final cards = payload()['cards'] as List;
      expect(cards, isNotEmpty);
      expect(cards.every((card) => card['route'] == '/m/page-$user'), isTrue);
      expect(
        payload()['accountFingerprint'],
        RemembranceWidgetService.accountFingerprint(user),
      );
      expect(cards.any((card) => card['kind'] == 'tasbeeh'), user != 'a');
      expect(cards.any((card) => card['kind'] == 'azkar'), user != 'a');
      final cached = await store.readCatalog(user);
      expect(
        cached.every(
          (card) =>
              card['ownerUserId'] == user && card['pageId'] == 'page-$user',
        ),
        isTrue,
      );
      expect(cards.any((card) => card.containsKey('ownerUserId')), isFalse);
    }
    active = 'a';
    await service.selectAccount(active);
    repos['page-a']!.offline = true;
    await service.refresh(active);
    expect(
      (payload()['cards'] as List).every(
        (card) => card['route'] == '/m/page-a',
      ),
      isTrue,
    );
    expect((await store.read(active)).hiddenTypes, {'azkar', 'tasbeeh'});
    active = 'b';
    expect((await store.read(active)).hiddenTypes, isEmpty);
    await expectLater(store.readCatalog('a'), throwsStateError);
  });

  test('a fresh device never inherits another account catalog', () async {
    final db = await openNewInMemoryDatabase();
    addTearDown(db.close);
    final store = RemembranceWidgetPreferencesStore(
      databaseProvider: () async => db,
      currentUserId: () => 'c',
    );
    expect(await store.readCatalog('c'), isEmpty);
    final service = _service(() => 'c', {'page-c': _Content('page-c')}, store);
    await service.refresh('c');
    expect(
      (payload()['cards'] as List).every(
        (card) => card['route'] == '/m/page-c',
      ),
      isTrue,
    );
  });

  test('selection is applied before the native card budget so later own texts remain selectable', () async {
    final db = await openNewInMemoryDatabase();
    addTearDown(db.close);
    final store = RemembranceWidgetPreferencesStore(
      databaseProvider: () async => db,
      currentUserId: () => 'a',
    );
    final repo = _Content('page-a')..azkarCount = 220;
    await store.save(
      'a',
      RemembranceWidgetPreferences(
        hiddenIds: {
          'memorial:page-a',
          for (var i = 0; i < 219; i++) 'azkar:page-a-azkar-$i',
        },
        hiddenTypes: {'dua', 'dedication', 'hadith', 'quran', 'tasbeeh'},
      ),
    );
    await _service(() => 'a', {'page-a': repo}, store).refresh('a');
    expect((await store.readCatalog('a')).length, greaterThan(200));
    final cards = payload()['cards'] as List;
    expect(cards, hasLength(1));
    expect(cards.single['id'], 'azkar:page-a-azkar-219:0');
  });

  test('an empty new account has no automatically imported public or default texts', () async {
    final service = _service(() => 'new-account', {}, null);
    await service.refresh('new-account');
    expect(payload()['cards'], isEmpty);
  });

  for (final returnToA in [false, true]) {
    test(
      'late refresh is rejected after switching account${returnToA ? ' and returning to the same account' : ''}',
      () async {
        var active = 'a';
        final old = _Content('old-a')..barrier = Completer<void>();
        final repos = {'page-a': old, 'page-b': _Content('page-b')};
        final service = _service(() => active, repos, null);
        await service.selectAccount('a');
        final pending = service.refresh('a');
        await old.started.future;
        active = 'b';
        await service.selectAccount(active);
        await service.refresh(active);
        if (returnToA) {
          active = 'a';
          repos['page-a'] = _Content('new-a');
          await service.selectAccount(active);
          await service.refresh(active);
        }
        final updates = calls
            .where((call) => call.method == 'updateRemembrance')
            .length;
        old.barrier!.complete();
        await pending;
        expect(
          calls.where((call) => call.method == 'updateRemembrance'),
          hasLength(updates),
        );
        expect(jsonEncode(payload()), isNot(contains('old-a')));
        expect(
          payload()['accountFingerprint'],
          RemembranceWidgetService.accountFingerprint(active),
        );
      },
    );
  }

  test(
    'legacy mixed and wrongly owned cached catalogs cannot be restored',
    () async {
      final db = await openNewInMemoryDatabase();
      addTearDown(db.close);
      final record = stringMapStoreFactory
          .store(LocalStores.preferences)
          .record('remembrance-widget-catalog:a');
      final store = RemembranceWidgetPreferencesStore(
        databaseProvider: () async => db,
        currentUserId: () => 'a',
      );
      await record.put(db, {
        'user': 'a',
        'cards': [
          {'id': 'foreign-public-text'},
        ],
      });
      expect(await store.readCatalog('a'), isEmpty);
      await record.put(db, {
        'version': 2,
        'user': 'a',
        'cards': [
          {'id': 'foreign', 'ownerUserId': 'b', 'pageId': 'page-b'},
        ],
      });
      await expectLater(store.readCatalog('a'), throwsStateError);
      await expectLater(
        store.saveCatalog('a', [
          {'ownerUserId': 'b', 'pageId': 'page-b'},
        ]),
        throwsStateError,
      );
    },
  );

  test('a session switch while opening local storage rejects a stale settings read', () async {
    final db = await openNewInMemoryDatabase();
    addTearDown(db.close);
    var active = 'a';
    final ready = Completer<Database>();
    final store = RemembranceWidgetPreferencesStore(
      databaseProvider: () => ready.future,
      currentUserId: () => active,
    );
    final reading = store.read('a');
    final assertion = expectLater(reading, throwsStateError);
    active = 'b';
    ready.complete(db);
    await assertion;
  });
}

RemembranceWidgetService _service(
  String? Function() active,
  Map<String, _Content> repos,
  RemembranceWidgetPreferencesStore? store,
) => RemembranceWidgetService(
  runtime: const MobileRuntime(
    isWeb: false,
    targetPlatform: TargetPlatform.android,
  ),
  currentUserId: active,
  preferencesStore: store,
  pageRepository: (id) => repos[id]!,
  memorialRepository: _Pages(),
);

class _Pages extends Fake implements MemorialPageRepository {
  @override
  Future<List<MemorialPage>> fetchOwnedPages() async => [
    for (final user in ['a', 'b', 'c'])
      MemorialPage(
        id: 'page-$user',
        ownerUserId: user,
        slug: 'page-$user',
        title: 'fixture-$user',
        deceasedName: 'fixture-person-$user',
        dedicationMessage: 'fixture-dedication-$user',
        isPublished: true,
      ),
    const MemorialPage(
      id: 'private-a',
      ownerUserId: 'a',
      slug: 'private-a',
      title: 'draft fixture',
    ),
  ];
}

class _Content extends Fake implements ContentRepository {
  _Content(this.label);
  final String label;
  bool offline = false;
  int azkarCount = 1;
  Completer<void>? barrier;
  final started = Completer<void>();
  @override
  Future<List<ContentItem>> fetchPublished(ContentType type) async {
    if (offline) throw StateError('offline');
    if (type == ContentType.azkar && barrier != null) {
      if (!started.isCompleted) started.complete();
      await barrier!.future;
    }
    if (type == ContentType.azkar && azkarCount > 1) {
      return [
        for (var i = 0; i < azkarCount; i++)
          ContentItem(
            id: '$label-azkar-$i',
            type: type,
            title: 'fixture $i',
            arabicText: 'fixture $label $i',
            isPublished: true,
          ),
      ];
    }
    return [
      ContentItem(
        id: '$label-${type.id}',
        type: type,
        title: 'fixture $label',
        arabicText: 'fixture $label ${type.id}',
        isPublished: true,
      ),
    ];
  }
}
