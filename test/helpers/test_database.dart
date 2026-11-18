import 'dart:io';

import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:get_it/get_it.dart';
import 'package:logger/logger.dart' show ConsoleOutput;

/// Opens a fresh ObjectBox store in a temp directory and binds the [Database] boxes to it.
///
/// [Database]'s boxes are `static late final`, so call this once per test file (each file runs in its own
/// isolate) and clear data between tests with [Database.reset].
Future<void> openTestDatabase() async {
  if (!GetIt.I.isRegistered<BaseLogger>()) {
    GetIt.I.registerSingleton<BaseLogger>(BaseLogger()..currentOutput = ConsoleOutput());
  }
  final dir = Directory.systemTemp.createTempSync('bb-test-db-');
  Database.store = await openStore(directory: dir.path);
  Database.bindBoxes();
}
