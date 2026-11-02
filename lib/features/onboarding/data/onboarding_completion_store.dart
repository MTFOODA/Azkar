import 'package:sembast/sembast.dart';

import '../../../core/storage/local_database.dart';
import '../../mobile_platform/domain/mobile_runtime.dart';

bool shouldShowFirstLaunchOnboarding({
  required MobileRuntime runtime,
  required String location,
  required bool completed,
}) => runtime.isNativeMobile && location == '/' && !completed;

class OnboardingCompletionStore {
  OnboardingCompletionStore({Future<Database> Function()? databaseProvider})
    : _databaseProvider = databaseProvider ?? LocalDatabase.instance;

  static const String recordKey = 'onboarding:completed:v1';

  final Future<Database> Function() _databaseProvider;
  final StoreRef<String, Object?> _store = StoreRef<String, Object?>(
    LocalStores.preferences,
  );

  Future<bool> isCompleted() async {
    final database = await _databaseProvider();
    return await _store.record(recordKey).get(database) == true;
  }

  Future<void> markCompleted() async {
    final database = await _databaseProvider();
    await _store.record(recordKey).put(database, true);
  }
}
