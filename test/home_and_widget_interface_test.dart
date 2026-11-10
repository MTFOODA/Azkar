import 'package:azkar/core/providers/app_providers.dart';
import 'package:azkar/core/widgets/asymmetric_card.dart';
import 'package:azkar/features/content/widgets/content_card.dart';
import 'package:azkar/features/home/presentation/home_page.dart';
import 'package:azkar/features/home_widget/data/prayer_home_widget_service.dart';
import 'package:azkar/features/home_widget/data/remembrance_widget_preferences.dart';
import 'package:azkar/features/home_widget/data/remembrance_widget_service.dart';
import 'package:azkar/features/home_widget/presentation/prayer_widget_actions.dart';
import 'package:azkar/features/home_widget/presentation/remembrance_widget_settings_page.dart';
import 'package:azkar/features/memorial/domain/memorial_page.dart';
import 'package:azkar/features/memorial/presentation/memorial_identity_card.dart';
import 'package:azkar/features/mobile_platform/domain/mobile_runtime.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('home shows only own named dedications and clears on sign-out', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        accountSessionProvider.overrideWith(_Session.new),
        ownedMemorialPagesProvider.overrideWith(
          (ref) async => const [
            MemorialPage(
              id: 'one',
              ownerUserId: 'owner',
              slug: 'one',
              title: 'one',
              deceasedName: 'أحمد',
              deceasedGender: 'male',
              dedicationMessage: 'دعاء أحمد',
              isPublished: true,
            ),
            MemorialPage(
              id: 'two',
              ownerUserId: 'owner',
              slug: 'two',
              title: 'two',
              deceasedName: 'فاطمة',
              deceasedGender: 'female',
              dedicationMessage: 'دعاء فاطمة',
            ),
            MemorialPage(
              id: 'foreign',
              ownerUserId: 'another',
              slug: 'foreign',
              title: 'other',
              deceasedName: 'اسم حساب آخر',
              isPublished: true,
            ),
            MemorialPage(
              id: 'blank',
              ownerUserId: 'owner',
              slug: 'blank',
              title: 'صفحة شخصية',
            ),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Scaffold(body: HomePage())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MemorialIdentityCard), findsNWidgets(2));
    expect(find.byType(AsymmetricCard), findsNWidgets(2));
    expect(find.text('المرحوم أحمد'), findsOneWidget);
    expect(find.text('المرحومة فاطمة'), findsOneWidget);
    expect(find.text('دعاء فاطمة'), findsOneWidget);
    expect(find.text('اسم حساب آخر'), findsNothing);
    expect(find.text('صفحة شخصية'), findsNothing);
    expect(find.text('فتح صفحة صدقة جارية'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(ContentCard), findsNothing);

    (container.read(accountSessionProvider.notifier) as _Session)
        .signOutLocally();
    await tester.pumpAndSettle();
    expect(find.byType(MemorialIdentityCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('one widget screen saves the selected content before pinning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final db = await openNewInMemoryDatabase();
    addTearDown(db.close);
    final store = RemembranceWidgetPreferencesStore(
      databaseProvider: () async => db,
    );
    final service = _RemembranceService(store);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSessionProvider.overrideWith(_Session.new),
          remembranceWidgetPreferencesStoreProvider.overrideWithValue(store),
          remembranceWidgetServiceProvider.overrideWithValue(service),
        ],
        child: const MaterialApp(home: RemembranceWidgetSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ويدجت الشاشة الرئيسية'), findsOneWidget);
    expect(find.text('إضافة ويدجت الأذكار والإهداء'), findsOneWidget);
    expect(find.text('المحتوى الظاهر في الويدجت'), findsOneWidget);
    expect(find.byType(FilterChip), findsNWidgets(6));
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.text('إضافة إلى الشاشة الرئيسية'), findsNothing);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('add-remembrance-widget')),
    );
    await tester.tap(find.byKey(const ValueKey('add-remembrance-widget')));
    await tester.pumpAndSettle();
    final saved = await tester.runAsync(() => store.read('owner'));
    expect(saved!.hiddenIds, {'azkar:one'});
    expect(service.hiddenWhenRefreshed, {'azkar:one'});
    expect(service.events, ['refresh', 'pin']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('widget screen without a session finishes loading safely', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          accountSessionProvider.overrideWith(_AnonymousSession.new),
          remembranceWidgetServiceProvider.overrideWithValue(
            _RemembranceService(null),
          ),
        ],
        child: const MaterialApp(home: RemembranceWidgetSettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('add-remembrance-widget')),
    );
    expect(button.onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'prayer controls refresh data before requesting the native widget',
    (tester) async {
      final service = _PrayerService();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            accountSessionProvider.overrideWith(_Session.new),
            prayerHomeWidgetServiceProvider.overrideWithValue(service),
          ],
          child: const MaterialApp(home: Scaffold(body: PrayerWidgetActions())),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('add-prayer-widget')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('refresh-prayer-widget')));
      await tester.pumpAndSettle();
      expect(service.events, ['refresh:owner', 'pin', 'refresh:owner']);
      expect(tester.takeException(), isNull);
    },
  );
}

class _Session extends AccountSessionController {
  void signOutLocally() => state = null;

  @override
  User? build() => User(
    id: 'owner',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
  );
}

class _AnonymousSession extends AccountSessionController {
  @override
  User? build() => null;
}

class _RemembranceService extends Fake implements RemembranceWidgetService {
  _RemembranceService(this.store);
  final RemembranceWidgetPreferencesStore? store;
  final events = <String>[];
  Set<String>? hiddenWhenRefreshed;
  @override
  MobileRuntime get runtime =>
      const MobileRuntime(isWeb: false, targetPlatform: TargetPlatform.android);
  @override
  Future<List<Map<String, Object?>>> loadAvailable(String userId) async => [
    {
      'id': 'azkar:one',
      'groupId': 'azkar:one',
      'kind': 'azkar',
      'title': 'ذكر',
      'text': 'سبحان الله',
    },
  ];
  @override
  Future<void> refresh(String userId) async {
    hiddenWhenRefreshed = (await store?.read(userId))?.hiddenIds;
    events.add('refresh');
  }

  @override
  Future<bool> requestPin() async {
    events.add('pin');
    return true;
  }
}

class _PrayerService extends Fake implements PrayerHomeWidgetService {
  final events = <String>[];
  @override
  bool get isSupported => true;
  @override
  Future<void> refresh(String userId) async => events.add('refresh:$userId');
  @override
  Future<bool> requestPin() async {
    events.add('pin');
    return true;
  }
}
