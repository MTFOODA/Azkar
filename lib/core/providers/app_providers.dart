import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sembast/sembast.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../data/local_theme_repository.dart';
import '../design/supabase_theme_repository.dart';
import '../design/theme_repository.dart';
import '../design/theme_settings.dart';
import '../storage/local_database.dart';
import '../typography/arabic_font_loader.dart';
import '../../features/admin/authentication/data/demo_admin_auth_service.dart';
import '../../features/admin/authentication/data/supabase_admin_auth_service.dart';
import '../../features/admin/authentication/domain/admin_auth_service.dart';
import '../../features/account/data/supabase_account_auth_service.dart';
import '../../features/account/domain/account_auth_service.dart';
import '../../features/content/data/content_repository.dart';
import '../../features/content/data/content_homepage_lifecycle.dart';
import '../../features/content/data/local_content_repository.dart';
import '../../features/content/data/supabase_content_repository.dart';
import '../../features/content/domain/content_item.dart';
import '../../features/content/domain/content_type.dart';
import '../../features/home/data/homepage_repository.dart';
import '../../features/home/data/local_homepage_repository.dart';
import '../../features/home/data/supabase_homepage_repository.dart';
import '../../features/home/domain/homepage_entry.dart';
import '../../features/memorial/data/memorial_page_repository.dart';
import '../../features/memorial/data/supabase_memorial_page_repository.dart';
import '../../features/memorial/domain/memorial_page.dart';
import '../../features/mobile_platform/domain/mobile_runtime.dart';
import '../../features/home_widget/data/prayer_home_widget_service.dart';
import '../../features/home_widget/data/remembrance_widget_service.dart';
import '../../features/home_widget/data/remembrance_widget_preferences.dart';
import '../../features/onboarding/data/onboarding_completion_store.dart';
import '../../features/notifications/data/flutter_local_notification_platform.dart';
import '../../features/notifications/data/local_notification_service.dart';
import '../../features/notifications/data/notification_schedule_registry.dart';
import '../../features/prayer_times/data/aladhan_prayer_times_provider.dart';
import '../../features/prayer_times/data/local_prayer_calendar_cache.dart';
import '../../features/prayer_times/data/prayer_times_provider.dart';
import '../../features/prayer_times/data/prayer_times_service.dart';
import '../../features/prayer_times/data/automatic_prayer_location_service.dart';
import '../../features/reminders/data/background_reminder_service.dart';
import '../../features/prayer_tracking/data/local_prayer_completion_store.dart';
import '../../features/prayer_tracking/data/local_prayer_completion_reminder_scheduler.dart';
import '../../features/prayer_tracking/data/prayer_completion_notification_coordinator.dart';
import '../../features/prayer_tracking/data/tasbeeh_event_notification_consumer.dart';
import '../../features/prayer_tracking/data/tasbeeh_outbox_coordinator.dart';
import '../../features/prayer_tracking/domain/prayer_completion_state_machine.dart';
import '../../features/reminders/data/local_prayer_schedule_location_store.dart';
import '../../features/reminders/data/local_reminder_scheduling_engine.dart';
import '../../features/reminders/data/local_reminder_preferences_store.dart';
import '../../features/reminders/data/reminder_preferences_remote_store.dart';
import '../../features/reminders/data/reminder_preferences_sync_service.dart';
import '../../features/reminders/data/supabase_reminder_preferences_store.dart';
import '../../features/reminders/domain/reminder_preferences.dart';
import '../../features/quran/data/quran_dataset_repository.dart';
import '../../features/tasbeeh/data/local_tasbeeh_counter_store.dart';
import '../../features/tasbeeh/domain/tasbeeh_counter_store.dart';
import '../utils/app_exception.dart';

/// Supabase is only touched when credentials were supplied at build time.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (AppConfig.useDemoBackend) return null;
  return Supabase.instance.client;
});

final prayerCalendarCacheProvider = Provider<PrayerCalendarCache>((ref) {
  return LocalPrayerCalendarCache();
});

final mobileRuntimeProvider = Provider<MobileRuntime>(
  (ref) => MobileRuntime.current(),
);

final onboardingCompletionStoreProvider = Provider<OnboardingCompletionStore>(
  (ref) => OnboardingCompletionStore(),
);

final prayerTimesProvider = Provider<PrayerTimesProvider>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return AlAdhanPrayerTimesProvider(client: client);
});

final prayerTimesServiceProvider = Provider<PrayerTimesService>((ref) {
  return PrayerTimesService(
    provider: ref.watch(prayerTimesProvider),
    cache: ref.watch(prayerCalendarCacheProvider),
  );
});

final reminderPreferencesLocalStoreProvider =
    Provider<ReminderPreferencesLocalStore>((ref) {
      return SembastReminderPreferencesStore(
        currentUserIdProvider: () => ref.read(accountSessionProvider)?.id,
      );
    });

final reminderPreferencesRemoteStoreProvider =
    Provider<ReminderPreferencesRemoteStore>((ref) {
      final client = ref.watch(supabaseClientProvider);
      if (client == null) {
        return const _OfflineReminderPreferencesRemoteStore();
      }
      return SupabaseReminderPreferencesStore(client);
    });

final reminderPreferencesSyncServiceProvider =
    Provider<ReminderPreferencesSyncService>((ref) {
      return ReminderPreferencesSyncService(
        localStore: ref.watch(reminderPreferencesLocalStoreProvider),
        remoteStore: ref.watch(reminderPreferencesRemoteStoreProvider),
        currentUserIdProvider: () => ref.read(accountSessionProvider)?.id,
      );
    });

final localPrayerCompletionStoreProvider = Provider<LocalPrayerCompletionStore>(
  (ref) {
    return LocalPrayerCompletionStore(
      currentUserIdProvider: () => ref.read(accountSessionProvider)?.id,
    );
  },
);

final localNotificationServiceProvider = Provider<LocalNotificationService>((
  ref,
) {
  final service = LocalNotificationService(
    platform: FlutterLocalNotificationPlatform(),
    registry: SembastNotificationScheduleRegistry(),
    currentUserIdProvider: () => ref.read(accountSessionProvider)?.id,
    runtime: MobileRuntime.current(),
  );
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

final prayerCompletionStateMachineProvider =
    Provider<PrayerCompletionStateMachine>((ref) {
      final machine = PrayerCompletionStateMachine(
        store: ref.watch(localPrayerCompletionStoreProvider),
        scheduler: LocalPrayerCompletionReminderScheduler(
          ref.watch(localNotificationServiceProvider),
        ),
        currentUserIdProvider: () => ref.read(accountSessionProvider)?.id,
      );
      ref.onDispose(() => unawaited(machine.dispose()));
      return machine;
    });

final prayerCompletionNotificationCoordinatorProvider =
    Provider<PrayerCompletionNotificationCoordinator>((ref) {
      final coordinator = PrayerCompletionNotificationCoordinator(
        stateMachine: ref.watch(prayerCompletionStateMachineProvider),
        notifications: ref.watch(localNotificationServiceProvider),
        currentUserIdProvider: () => ref.read(accountSessionProvider)?.id,
      );
      ref.onDispose(() => unawaited(coordinator.dispose()));
      return coordinator;
    });

final tasbeehEventNotificationConsumerProvider =
    Provider<TasbeehEventNotificationConsumer>((ref) {
      return TasbeehEventNotificationConsumer(
        notifications: ref.watch(localNotificationServiceProvider),
        preferencesStore: ref.watch(reminderPreferencesLocalStoreProvider),
        currentUserIdProvider: () => ref.read(accountSessionProvider)?.id,
      );
    });

final tasbeehOutboxCoordinatorProvider = Provider<TasbeehOutboxCoordinator>((
  ref,
) {
  final coordinator = TasbeehOutboxCoordinator(
    stateMachine: ref.watch(prayerCompletionStateMachineProvider),
    consumer: ref.watch(tasbeehEventNotificationConsumerProvider).handle,
    currentUserIdProvider: () => ref.read(accountSessionProvider)?.id,
  );
  ref.onDispose(() => unawaited(coordinator.dispose()));
  return coordinator;
});

final localPrayerScheduleLocationStoreProvider =
    Provider<LocalPrayerScheduleLocationStore>((ref) {
      return LocalPrayerScheduleLocationStore(
        currentUserIdProvider: () => ref.read(accountSessionProvider)?.id,
        allowManualLocation: false,
      );
    });

final localReminderSchedulingEngineProvider =
    Provider<LocalReminderSchedulingEngine>((ref) {
      return LocalReminderSchedulingEngine(
        preferencesStore: ref.watch(reminderPreferencesLocalStoreProvider),
        locationStore: ref.watch(localPrayerScheduleLocationStoreProvider),
        prayerTimesService: ref.watch(prayerTimesServiceProvider),
        notifications: ref.watch(localNotificationServiceProvider),
        prayerCompletionStateMachine: ref.watch(
          prayerCompletionStateMachineProvider,
        ),
        currentUserIdProvider: () => ref.read(accountSessionProvider)?.id,
        refreshHomeWidget: ref.watch(prayerHomeWidgetServiceProvider).refresh,
        persistBackgroundSnapshot: ref
            .watch(backgroundReminderServiceProvider)
            .save,
      );
    });

final backgroundReminderServiceProvider = Provider<BackgroundReminderService>((
  ref,
) {
  final service = BackgroundReminderService(
    runtime: ref.watch(mobileRuntimeProvider),
    currentUserId: () => ref.read(accountSessionProvider)?.id,
  );
  ref.onDispose(service.dispose);
  return service;
});

final automaticPrayerLocationServiceProvider =
    Provider<AutomaticPrayerLocationService>(
      (ref) => AutomaticPrayerLocationService(
        ref.watch(localPrayerScheduleLocationStoreProvider),
        () => ref.read(accountSessionProvider)?.id,
      ),
    );

final prayerHomeWidgetServiceProvider = Provider<PrayerHomeWidgetService>((
  ref,
) {
  return PrayerHomeWidgetService(
    preferencesStore: ref.watch(reminderPreferencesLocalStoreProvider),
    locationStore: ref.watch(localPrayerScheduleLocationStoreProvider),
    prayerTimesService: ref.watch(prayerTimesServiceProvider),
    currentUserIdProvider: () => ref.read(accountSessionProvider)?.id,
    runtime: ref.watch(mobileRuntimeProvider),
  );
});

final remembranceWidgetServiceProvider = Provider<RemembranceWidgetService>(
  (ref) => RemembranceWidgetService(
    runtime: ref.watch(mobileRuntimeProvider),
    currentUserId: () => ref.read(accountSessionProvider)?.id,
    globalRepository: ref.watch(contentRepositoryProvider),
    pageRepository: (id) => ref.read(pageContentRepositoryProvider(id)),
    memorialRepository: ref.watch(memorialPageRepositoryProvider),
    preferencesStore: ref.watch(remembranceWidgetPreferencesStoreProvider),
  ),
  dependencies: [contentRepositoryProvider, pageContentRepositoryProvider],
);

final remembranceWidgetPreferencesStoreProvider =
    Provider<RemembranceWidgetPreferencesStore>(
      (ref) => RemembranceWidgetPreferencesStore(
        currentUserId: () => ref.read(accountSessionProvider)?.id,
      ),
    );

class _OfflineReminderPreferencesRemoteStore
    implements ReminderPreferencesRemoteStore {
  const _OfflineReminderPreferencesRemoteStore();

  Never _offline() => throw http.ClientException(
    'Reminder preference sync requires a configured authenticated backend.',
  );

  @override
  Future<ReminderPreferencesSnapshot?> fetch(String userId) async => _offline();

  @override
  Future<ReminderPreferencesSaveResult> save({
    required String userId,
    required ReminderPreferences preferences,
    required int expectedRevision,
  }) async => _offline();
}

final themeRepositoryProvider = Provider<ThemeRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? LocalThemeRepository()
      : SupabaseThemeRepository(client);
}, dependencies: []);

final contentRepositoryProvider = Provider<ContentRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? LocalContentRepository(
          themeProvider: () => ref.read(themeSettingsProvider),
        )
      : SupabaseContentRepository(
          client: client,
          themeProvider: () => ref.read(themeSettingsProvider),
        );
}, dependencies: [themeSettingsProvider]);

final pageContentRepositoryProvider =
    Provider.family<ContentRepository, String>((ref, pageId) {
      final client = ref.watch(supabaseClientProvider);
      return client == null
          ? LocalContentRepository(
              pageId: pageId,
              themeProvider: () => ref.read(themeSettingsProvider),
            )
          : SupabaseContentRepository(
              client: client,
              pageId: pageId,
              themeProvider: () => ref.read(themeSettingsProvider),
            );
    }, dependencies: [themeSettingsProvider]);

final homepageRepositoryProvider = Provider<HomepageRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? LocalHomepageRepository(
          contentRepository: ref.watch(contentRepositoryProvider),
        )
      : SupabaseHomepageRepository(
          client: client,
          themeProvider: () => ref.read(themeSettingsProvider),
        );
}, dependencies: [contentRepositoryProvider, themeSettingsProvider]);

final pageHomepageRepositoryProvider =
    Provider.family<HomepageRepository, String>((ref, pageId) {
      final client = ref.watch(supabaseClientProvider);
      final contentRepository = ref.watch(
        pageContentRepositoryProvider(pageId),
      );
      return client == null
          ? LocalHomepageRepository(
              pageId: pageId,
              contentRepository: contentRepository,
            )
          : SupabaseHomepageRepository(
              client: client,
              pageId: pageId,
              themeProvider: () => ref.read(themeSettingsProvider),
            );
    }, dependencies: [pageContentRepositoryProvider, themeSettingsProvider]);

final contentHomepageLifecycleProvider = Provider<ContentHomepageLifecycle>((
  ref,
) {
  return ContentHomepageLifecycle(
    contentRepository: ref.watch(contentRepositoryProvider),
    homepageRepository: ref.watch(homepageRepositoryProvider),
  );
}, dependencies: [contentRepositoryProvider, homepageRepositoryProvider]);

final pageThemeRepositoryProvider = Provider.family<ThemeRepository, String>((
  ref,
  pageId,
) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? LocalThemeRepository(pageId: pageId)
      : SupabaseThemeRepository(client, pageId: pageId);
});

final pageThemeSettingsProvider = FutureProvider.family<ThemeSettings?, String>(
  (ref, pageId) {
    return ref.watch(pageThemeRepositoryProvider(pageId)).load();
  },
);

final memorialPageRepositoryProvider = Provider<MemorialPageRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? const UnconfiguredMemorialPageRepository()
      : SupabaseMemorialPageRepository(client);
});

final ownedMemorialPagesProvider = FutureProvider<List<MemorialPage>>((ref) {
  final userId = ref.watch(accountSessionProvider.select((user) => user?.id));
  if (userId == null) return const <MemorialPage>[];
  return ref.watch(memorialPageRepositoryProvider).fetchOwnedPages().then((
    pages,
  ) {
    if (pages.any((page) => page.ownerUserId != userId)) {
      throw const NotAuthorizedException();
    }
    return pages;
  });
});

final ownedMemorialPageProvider = FutureProvider.family<MemorialPage?, String>((
  ref,
  pageId,
) {
  final userId = ref.watch(accountSessionProvider.select((user) => user?.id));
  if (userId == null) return null;
  return ref.watch(memorialPageRepositoryProvider).fetchOwnedById(pageId).then((
    page,
  ) {
    if (page != null && (page.id != pageId || page.ownerUserId != userId)) {
      throw const NotAuthorizedException();
    }
    return page;
  });
});

final selectedMemorialPageProvider = Provider<MemorialPage?>((ref) => null);

final publicMemorialPageProvider = FutureProvider.family<MemorialPage?, String>(
  (ref, slug) {
    return ref.watch(memorialPageRepositoryProvider).fetchPublishedBySlug(slug);
  },
);

final publicMemorialLayoutProvider =
    FutureProvider.family<List<HomeCard>, String>((ref, pageId) async {
      final cards = await ref
          .watch(pageHomepageRepositoryProvider(pageId))
          .fetchPublishedLayout();
      await ArabicFontLoader.ensureAll(
        cards.map((card) => card.item.style.fontFamily),
      );
      return cards;
    }, dependencies: [pageHomepageRepositoryProvider]);

final pagePublishedContentProvider =
    FutureProvider.family<
      List<ContentItem>,
      ({String pageId, ContentType type})
    >((ref, key) async {
      final items = await ref
          .watch(pageContentRepositoryProvider(key.pageId))
          .fetchPublished(key.type);
      await ArabicFontLoader.ensureAll(
        items.map((item) => item.style.fontFamily),
      );
      return items;
    }, dependencies: [pageContentRepositoryProvider]);

final accountAuthServiceProvider = Provider<AccountAuthService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? const UnconfiguredAccountAuthService()
      : SupabaseAccountAuthService(client);
});

class UnconfiguredAccountAuthService implements AccountAuthService {
  const UnconfiguredAccountAuthService();

  Never _unavailable() => throw const AppException(
    'يتطلب إنشاء الحسابات وتسجيل الدخول ربط التطبيق بمشروع Supabase.',
  );

  @override
  Future<bool> register({
    required String displayName,
    required String email,
    required String password,
  }) async => _unavailable();

  @override
  Future<void> signIn({
    required String email,
    required String password,
  }) async => _unavailable();

  @override
  Future<void> sendPasswordReset(String email) async => _unavailable();

  @override
  Future<void> updatePassword(String password) async => _unavailable();

  @override
  Future<void> signOut() async => _unavailable();
}

class AccountSessionController extends Notifier<User?> {
  StreamSubscription<AuthState>? _subscription;

  @override
  User? build() {
    final client = ref.watch(supabaseClientProvider);
    _subscription?.cancel();
    if (client == null) return null;
    _subscription = client.auth.onAuthStateChange.listen((event) {
      state = event.session?.user;
    });
    ref.onDispose(() => _subscription?.cancel());
    return client.auth.currentUser;
  }

  Future<bool> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    final verifiedImmediately = await ref
        .read(accountAuthServiceProvider)
        .register(displayName: displayName, email: email, password: password);
    state = ref.read(supabaseClientProvider)?.auth.currentUser;
    return verifiedImmediately;
  }

  Future<void> signIn({required String email, required String password}) async {
    await ref
        .read(accountAuthServiceProvider)
        .signIn(email: email, password: password);
    state = ref.read(supabaseClientProvider)?.auth.currentUser;
  }

  Future<void> sendPasswordReset(String email) =>
      ref.read(accountAuthServiceProvider).sendPasswordReset(email);

  Future<void> updatePassword(String password) =>
      ref.read(accountAuthServiceProvider).updatePassword(password);

  Future<void> signOut() async {
    await ref.read(accountAuthServiceProvider).signOut();
    state = null;
  }
}

final accountSessionProvider =
    NotifierProvider<AccountSessionController, User?>(
      AccountSessionController.new,
    );

final adminAuthServiceProvider = Provider<AdminAuthService>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? DemoAdminAuthService(
          email: AppConfig.demoAdminEmail,
          password: AppConfig.demoAdminPassword,
        )
      : SupabaseAdminAuthService(client);
});

final quranDatasetRepositoryProvider = Provider<QuranDatasetRepository>((ref) {
  return QuranDatasetRepository();
});

final tasbeehCounterStoreProvider = Provider<TasbeehCounterStore>((ref) {
  return LocalTasbeehCounterStore();
});

/// Global appearance state. The settings row is loaded once at startup and can
/// be replaced live from the appearance editor.
class ThemeSettingsNotifier extends Notifier<ThemeSettings> {
  bool _loaded = false;

  @override
  ThemeSettings build() {
    if (!_loaded) {
      _loaded = true;
      unawaited(_load());
    }
    return ThemeSettings.defaults;
  }

  Future<void> _load() async {
    try {
      final loaded = await ref.read(themeRepositoryProvider).load();
      if (loaded != null) {
        state = loaded;
        await ArabicFontLoader.ensure(loaded.defaultFontId);
      }
    } catch (error) {
      // Defaults are a safe, readable fallback; the public site must still open
      // when the theme row is unavailable.
      debugPrint('Theme settings unavailable: $error');
    }
  }

  Future<ThemeSettings> update(ThemeSettings settings) async {
    await ArabicFontLoader.ensure(settings.defaultFontId);
    final saved = await ref.read(themeRepositoryProvider).save(settings);
    state = saved;
    return saved;
  }
}

final themeSettingsProvider =
    NotifierProvider<ThemeSettingsNotifier, ThemeSettings>(
      ThemeSettingsNotifier.new,
      dependencies: [themeRepositoryProvider],
    );

/// Light/dark/system preference, stored locally per visitor.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const String _key = 'theme_mode';
  bool _loaded = false;

  @override
  ThemeMode build() {
    if (!_loaded) {
      _loaded = true;
      unawaited(_load());
    }
    return ThemeMode.system;
  }

  Future<void> _load() async {
    try {
      final database = await LocalDatabase.instance();
      final store = StoreRef<String, Object?>(LocalStores.preferences);
      final value = await store.record(_key).get(database);
      state = switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {
      // System mode remains the fallback.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      final database = await LocalDatabase.instance();
      final store = StoreRef<String, Object?>(LocalStores.preferences);
      await store.record(_key).put(database, mode.name);
    } catch (_) {
      // A storage failure must not prevent the visitor from using the site.
    }
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

/// Synchronous session state for route guards, backed by the auth service's
/// stream for restore/sign-in/sign-out events.
class AdminSessionController extends Notifier<AdminSession?> {
  StreamSubscription<AdminSession?>? _subscription;

  @override
  AdminSession? build() {
    final service = ref.watch(adminAuthServiceProvider);
    _subscription?.cancel();
    _subscription = service.authStateChanges().listen((session) {
      state = session;
    });
    ref.onDispose(() => _subscription?.cancel());
    return service.currentSession;
  }

  Future<AdminSession> signInDemo({
    required String email,
    required String password,
  }) async {
    final service = ref.read(adminAuthServiceProvider);
    if (service is! DemoAdminAuthService) {
      throw StateError('Demo administrator login is unavailable.');
    }
    final session = await service.signInWithPassword(
      email: email,
      password: password,
    );
    state = session;
    return session;
  }

  Future<AdminSession?> refreshCurrentUser() async {
    final session = await ref
        .read(adminAuthServiceProvider)
        .currentSessionForSignedInUser();
    state = session;
    return session;
  }

  Future<void> signOut() async {
    await ref.read(adminAuthServiceProvider).signOut();
    state = null;
  }
}

final adminSessionProvider =
    NotifierProvider<AdminSessionController, AdminSession?>(
      AdminSessionController.new,
    );

final isDemoBackendProvider = Provider<bool>((ref) => AppConfig.useDemoBackend);

final registrationUnavailableMessageProvider = Provider<String?>((ref) {
  return AppConfig.registrationUnavailableMessage(
    demoMode: ref.watch(isDemoBackendProvider),
    schemaVerified: AppConfig.authSchemaVerified,
  );
});

final isRegistrationEnabledProvider = Provider<bool>(
  (ref) => ref.watch(registrationUnavailableMessageProvider) == null,
);
