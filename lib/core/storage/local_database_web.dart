import 'package:sembast_web/sembast_web.dart';

/// Flutter Web implementation: IndexedDB-backed.
Future<Database> openLocalDatabase(String name) =>
    databaseFactoryWeb.openDatabase(name);
