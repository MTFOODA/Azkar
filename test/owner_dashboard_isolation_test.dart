import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/core/utils/app_exception.dart';
import 'package:azkar/features/admin/content_management/providers/admin_providers.dart';
import 'package:azkar/features/content/data/content_repository.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/features/content/domain/content_type.dart';
import 'package:azkar/core/design/theme_repository.dart';
import 'package:azkar/core/design/theme_settings.dart';
import 'package:azkar/features/memorial/data/memorial_page_repository.dart';
import 'package:azkar/features/memorial/domain/memorial_page.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'owner content providers use the page-scoped repository override',
    () async {
      final root = ProviderContainer(
        overrides: [
          contentRepositoryProvider.overrideWithValue(
            _ItemsRepository('primary-page'),
          ),
        ],
      );
      final ownerScope = ProviderContainer(
        parent: root,
        overrides: [
          contentRepositoryProvider.overrideWithValue(
            _ItemsRepository('secondary-page'),
          ),
        ],
      );
      addTearDown(ownerScope.dispose);
      addTearDown(root.dispose);

      final items = await ownerScope.read(
        adminContentProvider(ContentType.azkar).future,
      );

      expect(items.map((item) => item.title), ['secondary-page']);
    },
  );

  test(
    'one account resolves two page IDs with separate content caches',
    () async {
      final session = _MutableAccountSession(_user('shared-owner'));
      final pages = _TwoMemorialPagesRepository();
      final container = ProviderContainer(
        overrides: [
          accountSessionProvider.overrideWith(() => session),
          memorialPageRepositoryProvider.overrideWithValue(pages),
          pageContentRepositoryProvider.overrideWith(
            (ref, pageId) => _ItemsRepository(pageId),
          ),
          pageThemeRepositoryProvider.overrideWith(
            (ref, pageId) => _PageThemeRepository(pageId),
          ),
        ],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);
      container.read(accountSessionProvider);

      final first = await container.read(
        ownedMemorialPageProvider('page-a').future,
      );
      final second = await container.read(
        ownedMemorialPageProvider('page-b').future,
      );
      final firstContent = await container
          .read(pageContentRepositoryProvider('page-a'))
          .fetchAll(ContentType.azkar);
      final secondContent = await container
          .read(pageContentRepositoryProvider('page-b'))
          .fetchAll(ContentType.azkar);
      final firstTheme = await container
          .read(pageThemeRepositoryProvider('page-a'))
          .load();
      final secondTheme = await container
          .read(pageThemeRepositoryProvider('page-b'))
          .load();

      expect(first?.deceasedName, 'Deceased A');
      expect(second?.deceasedName, 'Deceased B');
      expect(firstContent.single.title, 'page-a');
      expect(secondContent.single.title, 'page-b');
      expect(firstTheme?.primaryColor, '#page-a');
      expect(secondTheme?.primaryColor, '#page-b');
    },
  );

  test(
    'switching account identity reloads only that account’s memorial pages',
    () async {
      final session = _MutableAccountSession(_user('primary-user'));
      final repository = _SessionMemorialPageRepository(() => session.userId);
      final container = ProviderContainer(
        overrides: [
          accountSessionProvider.overrideWith(() => session),
          memorialPageRepositoryProvider.overrideWithValue(repository),
        ],
        retry: (_, _) => null,
      );
      addTearDown(container.dispose);

      container.read(accountSessionProvider);
      final primaryPages = await container.read(
        ownedMemorialPagesProvider.future,
      );
      session.setUser(_user('secondary-user'));
      final secondaryPages = await container.read(
        ownedMemorialPagesProvider.future,
      );
      session.setUser(null);
      final signedOutPages = await container.read(
        ownedMemorialPagesProvider.future,
      );

      expect(primaryPages.single.ownerUserId, 'primary-user');
      expect(secondaryPages.single.ownerUserId, 'secondary-user');
      expect(signedOutPages, isEmpty);
      expect(repository.requestedOwners, ['primary-user', 'secondary-user']);
    },
  );

  test('a page returned for the wrong owner fails closed', () async {
    final session = _MutableAccountSession(_user('secondary-user'));
    final repository = _SessionMemorialPageRepository(() => 'primary-user');
    final container = ProviderContainer(
      overrides: [
        accountSessionProvider.overrideWith(() => session),
        memorialPageRepositoryProvider.overrideWithValue(repository),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);

    container.read(accountSessionProvider);

    await expectLater(
      container.read(ownedMemorialPageProvider('page-primary-user').future),
      throwsA(isA<NotAuthorizedException>()),
    );
  });
}

class _ItemsRepository implements ContentRepository {
  _ItemsRepository(this.owner);

  final String owner;

  @override
  Future<List<ContentItem>> fetchAll(ContentType type) async => [
    ContentItem(id: '$owner-item', type: type, title: owner),
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MutableAccountSession extends AccountSessionController {
  _MutableAccountSession(this._initialUser) : userId = _initialUser.id;

  final User _initialUser;
  String? userId;

  @override
  User? build() => _initialUser;

  void setUser(User? user) {
    userId = user?.id;
    state = user;
  }
}

class _SessionMemorialPageRepository implements MemorialPageRepository {
  _SessionMemorialPageRepository(this._userId);

  final String? Function() _userId;
  final requestedOwners = <String?>[];

  @override
  Future<List<MemorialPage>> fetchOwnedPages() async {
    final owner = _userId();
    requestedOwners.add(owner);
    if (owner == null) return const [];
    return [
      MemorialPage(
        id: 'page-$owner',
        ownerUserId: owner,
        slug: 'page-$owner',
        title: 'Page $owner',
      ),
    ];
  }

  @override
  Future<MemorialPage?> fetchOwnedById(String pageId) async {
    final owner = _userId();
    if (owner == null) return null;
    return MemorialPage(
      id: pageId,
      ownerUserId: owner,
      slug: pageId,
      title: 'Page $owner',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TwoMemorialPagesRepository implements MemorialPageRepository {
  final pages = [
    MemorialPage(
      id: 'page-a',
      ownerUserId: 'shared-owner',
      slug: 'deceased-a',
      title: 'Page A',
      deceasedName: 'Deceased A',
    ),
    MemorialPage(
      id: 'page-b',
      ownerUserId: 'shared-owner',
      slug: 'deceased-b',
      title: 'Page B',
      deceasedName: 'Deceased B',
    ),
  ];

  @override
  Future<List<MemorialPage>> fetchOwnedPages() async => pages;

  @override
  Future<MemorialPage?> fetchOwnedById(String pageId) async {
    for (final page in pages) {
      if (page.id == pageId) return page;
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PageThemeRepository implements ThemeRepository {
  _PageThemeRepository(this.pageId);

  final String pageId;

  @override
  Future<ThemeSettings?> load() async =>
      ThemeSettings(primaryColor: '#$pageId');

  @override
  Future<ThemeSettings> save(ThemeSettings settings) async => settings;
}

User _user(String id) => User(
  id: id,
  appMetadata: const {},
  userMetadata: const {},
  aud: 'authenticated',
  email: '$id@example.test',
  createdAt: '2026-01-01T00:00:00.000Z',
);
