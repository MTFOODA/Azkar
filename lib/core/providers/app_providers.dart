import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../features/quran/data/quran_dataset_repository.dart';
import '../../features/tasbeeh/data/local_tasbeeh_counter_store.dart';
import '../../features/tasbeeh/domain/tasbeeh_counter_store.dart';
import '../utils/app_exception.dart';

/// Supabase is only touched when credentials were supplied at build time.
final supabaseClientProvider = Provider<SupabaseClient?>((ref) {
  if (AppConfig.useDemoBackend) return null;
  return Supabase.instance.client;
});

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

final currentMemorialPageProvider = FutureProvider<MemorialPage?>((ref) {
  final userId = ref.watch(accountSessionProvider.select((user) => user?.id));
  if (userId == null) return null;
  return ref.watch(memorialPageRepositoryProvider).fetchMine().then((page) {
    if (page != null && page.ownerUserId != userId) {
      throw const NotAuthorizedException();
    }
    return page;
  });
});

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
