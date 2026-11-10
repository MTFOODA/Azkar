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
  static const _catalogVersion = 2;
  void _validate(String user) {
    if (user.trim().isEmpty ||
        (currentUserId != null && currentUserId!() != user)) {
      throw StateError('Widget settings require their active account.');
    }
  }

  Future<RemembranceWidgetPreferences> read(String user) async {
    _validate(user);
    final database = await _databaseProvider();
    _validate(user);
    final row = await _store
        .record('remembrance-widget-settings:$user')
        .get(database);
    _validate(user);
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
    final database = await _databaseProvider();
    _validate(user);
    await _store.record('remembrance-widget-settings:$user').put(database, {
      'user': user,
      'hidden_ids': settings.hiddenIds.toList(),
      'hidden_types': settings.hiddenTypes.toList(),
    });
  }

  Future<void> saveCatalog(
    String user,
    List<Map<String, Object?>> cards,
  ) async {
    _validate(user);
    if (cards.any(
      (card) =>
          card['ownerUserId'] != user ||
          card['pageId'] is! String ||
          (card['pageId'] as String).isEmpty,
    )) {
      throw StateError('Widget catalog contains content outside its account.');
    }
    final database = await _databaseProvider();
    _validate(user);
    await _store.record('remembrance-widget-catalog:$user').put(database, {
      'version': _catalogVersion,
      'user': user,
      'cards': cards,
    });
  }

  Future<List<Map<String, Object?>>> readCatalog(String user) async {
    _validate(user);
    final database = await _databaseProvider();
    _validate(user);
    final row = await _store
        .record('remembrance-widget-catalog:$user')
        .get(database);
    _validate(user);
    if (row == null) return [];
    if (row['user'] != user) {
      throw StateError('Mismatched widget catalog owner.');
    }
    // Older catalogs mixed global/public records into an account's list.
    // Never restore those snapshots, including when the device is offline.
    if (row['version'] != _catalogVersion) return [];
    final cards = (row['cards'] as List)
        .whereType<Map>()
        .map((item) => Map<String, Object?>.from(item))
        .toList();
    if (cards.any(
      (card) =>
          card['ownerUserId'] != user ||
          card['pageId'] is! String ||
          (card['pageId'] as String).isEmpty,
    )) {
      throw StateError('Mismatched widget catalog content owner.');
    }
    return cards;
  }
}
