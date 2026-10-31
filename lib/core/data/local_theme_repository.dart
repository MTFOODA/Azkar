import 'package:sembast/sembast.dart';

import '../../core/storage/local_database.dart';
import '../design/theme_repository.dart';
import '../design/theme_settings.dart';

/// Locally persisted appearance settings for the offline/demo backend.
class LocalThemeRepository implements ThemeRepository {
  LocalThemeRepository({
    Future<Database> Function()? databaseProvider,
    this._pageId,
  }) : _databaseProvider = databaseProvider ?? LocalDatabase.instance;

  final Future<Database> Function() _databaseProvider;
  final String? _pageId;

  String get _key =>
      _pageId == null ? 'theme_settings' : 'theme_settings_$_pageId';
  StoreRef<String, Object?> get _preferences =>
      StoreRef<String, Object?>(LocalStores.preferences);

  @override
  Future<ThemeSettings?> load() async {
    final database = await _databaseProvider();
    final raw = await _preferences.record(_key).get(database);
    if (raw is! Map) return null;
    return ThemeSettings.fromMap(Map<String, dynamic>.from(raw));
  }

  @override
  Future<ThemeSettings> save(ThemeSettings settings) async {
    final database = await _databaseProvider();
    await _preferences.record(_key).put(database, settings.toMap());
    return settings.copyWith(updatedAt: DateTime.now().toUtc());
  }
}
