import 'package:azkar/core/config/app_config.dart';
import 'package:azkar/core/design/theme_repository.dart';
import 'package:azkar/core/design/theme_settings.dart';
import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/core/utils/app_exception.dart';
import 'package:azkar/features/admin/content_management/providers/admin_providers.dart';
import 'package:azkar/features/content/data/content_repository.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/features/memorial/data/memorial_page_repository.dart';
import 'package:azkar/features/memorial/data/supabase_memorial_page_repository.dart';
import 'package:azkar/features/memorial/domain/memorial_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('registration gate', () {
    test('local development is not blocked by the production flag', () {
      expect(
        AppConfig.schemaGateMessage(
          schemaVerified: false,
          productionBuild: false,
        ),
        isNull,
      );
    });

    test('production builds stay closed until the schema is verified', () {
      expect(
        AppConfig.schemaGateMessage(
          schemaVerified: false,
          productionBuild: true,
        ),
        contains('AZKAR_AUTH_SCHEMA_VERIFIED=true'),
      );
      expect(
        AppConfig.schemaGateMessage(
          schemaVerified: true,
          productionBuild: true,
        ),
        isNull,
      );
    });
  });

  group('owner scopes (real nested ProviderScope)', () {
    testWidgets('two accounts get independent content, counts and themes', (
      tester,
    ) async {
      final containers = <String, ProviderContainer>{};

      Widget scope(String owner) => ProviderScope(
        key: ValueKey(owner),
        overrides: [
          contentRepositoryProvider.overrideWithValue(
            _FakeContent(owner, published: owner == 'a' ? 3 : 1),
          ),
          themeRepositoryProvider.overrideWithValue(
            _FakeTheme(owner == 'a' ? '#111111' : '#222222'),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            containers[owner] = ProviderScope.containerOf(context);
            ref.watch(themeSettingsProvider);
            return const SizedBox();
          },
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            contentRepositoryProvider.overrideWithValue(_FakeContent('root')),
            themeRepositoryProvider.overrideWithValue(_FakeTheme('#000000')),
          ],
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Column(children: [scope('a'), scope('b')]),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      final a = containers['a']!;
      final b = containers['b']!;
      final dashboardA = await a.read(adminDashboardProvider.future);
      final dashboardB = await b.read(adminDashboardProvider.future);
      expect(dashboardA.published, 3 * ContentType.values.length);
      expect(dashboardB.published, ContentType.values.length);
      expect(
        dashboardA.recent.every((item) => item.title == 'a'),
        isTrue,
        reason: 'Account A must only see its own records.',
      );
      expect(
        (await b.read(adminContentProvider(ContentType.azkar).future))
            .single
            .title,
        'b',
      );
      expect(a.read(themeSettingsProvider).primaryColor, '#111111');
      expect(b.read(themeSettingsProvider).primaryColor, '#222222');
    });
  });

  group('memorial ownership', () {
    test(
      'writes without an authenticated owner are rejected locally',
      () async {
        final client = SupabaseClient('http://localhost:1', 'sb_publishable_x');
        addTearDown(client.dispose);
        final repository = SupabaseMemorialPageRepository(client);
        final foreignPage = MemorialPage(
          id: 'page-b',
          ownerUserId: 'user-b',
          slug: 'page-b',
          title: 'B',
        );

        await expectLater(
          repository.update(foreignPage),
          throwsA(isA<NotAuthorizedException>()),
        );
        await expectLater(
          repository.fetchOwnedPages(),
          throwsA(isA<NotAuthorizedException>()),
        );
        await expectLater(
          repository.fetchOwnedById('page-b'),
          throwsA(isA<NotAuthorizedException>()),
        );
      },
    );

    test(
      'sign-out clears owned pages and a new user reloads their pages',
      () async {
        final session = _Session(_user('user-a'));
        final repository = _PerUserPages(() => session.userId);
        final container = ProviderContainer(
          overrides: [
            accountSessionProvider.overrideWith(() => session),
            memorialPageRepositoryProvider.overrideWithValue(repository),
          ],
          retry: (_, _) => null,
        );
        addTearDown(container.dispose);
        container.read(accountSessionProvider);

        expect(
          (await container.read(ownedMemorialPagesProvider.future))
              .map((page) => page.id)
              .toList(),
          ['page-user-a-1', 'page-user-a-2'],
        );
        session.setUser(null);
        expect(
          await container.read(ownedMemorialPagesProvider.future),
          isEmpty,
        );
        session.setUser(_user('user-b'));
        final pagesB = await container.read(ownedMemorialPagesProvider.future);
        expect(pagesB.map((page) => page.id), [
          'page-user-b-1',
          'page-user-b-2',
        ]);
        expect(pagesB.every((page) => page.ownerUserId == 'user-b'), isTrue);
        expect(
          await container.read(
            ownedMemorialPageProvider('page-user-b-2').future,
          ),
          isNotNull,
        );
      },
    );
  });
}

class _FakeContent implements ContentRepository {
  _FakeContent(this.owner, {this.published = 0});

  final String owner;
  final int published;

  @override
  Future<List<ContentItem>> fetchAll(ContentType type) async => [
    ContentItem(id: '$owner-${type.id}', type: type, title: owner),
  ];

  @override
  Future<Map<ContentType, TypeCounts>> counts() async => {
    for (final type in ContentType.values)
      type: TypeCounts(published: published, drafts: 0),
  };

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTheme implements ThemeRepository {
  _FakeTheme(this.primary);

  final String primary;

  @override
  Future<ThemeSettings?> load() async => ThemeSettings(primaryColor: primary);

  @override
  Future<ThemeSettings> save(ThemeSettings settings) async => settings;
}

class _Session extends AccountSessionController {
  _Session(this._initial) : userId = _initial.id;

  final User _initial;
  String? userId;

  @override
  User? build() => _initial;

  void setUser(User? user) {
    userId = user?.id;
    state = user;
  }
}

class _PerUserPages implements MemorialPageRepository {
  _PerUserPages(this._userId);

  final String? Function() _userId;

  @override
  Future<List<MemorialPage>> fetchOwnedPages() async {
    final owner = _userId();
    if (owner == null) return const [];
    return [
      for (var index = 1; index <= 2; index++)
        MemorialPage(
          id: 'page-$owner-$index',
          ownerUserId: owner,
          slug: 'page-$owner-$index',
          title: 'Page $owner $index',
        ),
    ];
  }

  @override
  Future<MemorialPage?> fetchOwnedById(String pageId) async {
    final pages = await fetchOwnedPages();
    for (final page in pages) {
      if (page.id == pageId) return page;
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  email: '$id@example.test',
  createdAt: '2026-01-01T00:00:00.000Z',
);
