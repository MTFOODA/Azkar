import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/core/utils/app_exception.dart';
import 'package:azkar/features/admin/content_management/providers/admin_providers.dart';
import 'package:azkar/features/content/data/content_repository.dart';
import 'package:azkar/features/content/domain/content_item.dart';
import 'package:azkar/features/content/domain/content_type.dart';
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
    'switching account identity reloads the current memorial page',
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
      final primaryPage = await container.read(
        currentMemorialPageProvider.future,
      );
      session.setUser(_user('secondary-user'));
      final secondaryPage = await container.read(
        currentMemorialPageProvider.future,
      );
      session.setUser(null);
      final signedOutPage = await container.read(
        currentMemorialPageProvider.future,
      );

      expect(primaryPage?.ownerUserId, 'primary-user');
      expect(secondaryPage?.ownerUserId, 'secondary-user');
      expect(signedOutPage, isNull);
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
      container.read(currentMemorialPageProvider.future),
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
  Future<MemorialPage?> fetchMine() async {
    final owner = _userId();
    requestedOwners.add(owner);
    if (owner == null) return null;
    return MemorialPage(
      id: 'page-$owner',
      ownerUserId: owner,
      slug: 'page-$owner',
      title: 'Page $owner',
    );
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
