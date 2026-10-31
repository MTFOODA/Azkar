import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast_io.dart';

/// Android / iOS implementation: an app-private file.
Future<Database> openLocalDatabase(String name) async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  final path = p.join(directory.path, name);
  return databaseFactoryIo.openDatabase(path);
}
