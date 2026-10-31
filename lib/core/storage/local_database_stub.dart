import 'package:sembast/sembast.dart';

/// Fallback used only when neither `dart:io` nor the web library is available
/// (for example a pure Dart test VM without a database factory configured).
Future<Database> openLocalDatabase(String name) {
  throw UnsupportedError(
    'No local database implementation is available on this platform.',
  );
}
