import 'package:sembast/sembast.dart';

import '../../../core/storage/local_database.dart';

class RemembranceWidgetPreferences {
  const RemembranceWidgetPreferences({
    this.hiddenIds = const {},
    this.hiddenTypes = const {},
  });
  final Set<String> hiddenIds;
  final Set<String> hiddenTypes;
  bool includes(Map<String, Object?> card) =>
      !hiddenIds.contains(card['groupId'] ?? card['id']) &&
      !hiddenTypes.contains(card['kind']);
}

class RemembranceWidgetPreferencesStore {
  RemembranceWidgetPreferencesStore({
    Future<Database> Function()? databaseProvider,
    this.currentUserId,
  }) : _databaseProvider = databaseProvider ?? LocalDatabase.instance;
  final Future<Database> Function() _databaseProvider;
  final String? Function()? currentUserId;
  final _store = stringMapStoreFactory.store(LocalStores.preferences);
  void _validate(String user) {
    if (user.trim().isEmpty ||
        (currentUserId != null && currentUserId!() != user)) {
      throw StateError('Widget settings require their active account.');
    }
  }

  Future<RemembranceWidgetPreferences> read(String user) async {
    _validate(user);
    final row = await _store
        .record('remembrance-widget-settings:$user')
        .get(await _databaseProvider());
    if (row == null) return const RemembranceWidgetPreferences();
    if (row['user'] != user) {
      throw StateError('Mismatched widget settings owner.');
    }
    return RemembranceWidgetPreferences(
      hiddenIds: Set.unmodifiable(
        (row['hidden_ids'] as List? ?? []).whereType<String>(),
      ),
      hiddenTypes: Set.unmodifiable(
        (row['hidden_types'] as List? ?? []).whereType<String>(),
      ),
    );
  }

  Future<void> save(String user, RemembranceWidgetPreferences settings) async {
    _validate(user);
    await _store.record('remembrance-widget-settings:$user').put(
      await _databaseProvider(),
      {
        'user': user,
        'hidden_ids': settings.hiddenIds.toList(),
        'hidden_types': settings.hiddenTypes.toList(),
      },
    );
  }

  Future<void> saveCatalog(
    String user,
    List<Map<String, Object?>> cards,
  ) async {
    _validate(user);
    await _store.record('remembrance-widget-catalog:$user').put(
      await _databaseProvider(),
      {'user': user, 'cards': cards},
    );
  }

  Future<List<Map<String, Object?>>> readCatalog(String user) async {
    _validate(user);
    final row = await _store
        .record('remembrance-widget-catalog:$user')
        .get(await _databaseProvider());
    if (row == null) return [];
    if (row['user'] != user) {
      throw StateError('Mismatched widget catalog owner.');
    }
    return (row['cards'] as List)
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList();
  }
}
