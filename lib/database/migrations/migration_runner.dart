import 'package:bluebubbles/utils/logger/logger.dart';

class MigrationRunner {
  /// Runs [migrate] for each version after [from] up to [to], saving each version once its step finishes.
  ///
  /// A step that throws stops the run and propagates; the last saved version is the one before it, so the
  /// failed step runs again on the next launch.
  static Future<void> run({
    required int from,
    required int to,
    required Future<void> Function(int version) migrate,
    required Future<void> Function(int version) saveVersion,
  }) async {
    if (from >= to) return;
    final stopwatch = Stopwatch()..start();
    Logger.debug("Performing database migration from version $from to $to", tag: "DB-Migration");
    for (int version = from + 1; version <= to; version++) {
      Logger.info("Migrating from version ${version - 1} to $version...", tag: "DB-Migration");
      await migrate(version);
      await saveVersion(version);
      Logger.info("Successfully migrated to version $version", tag: "DB-Migration");
    }
    Logger.info("Completed database migration in ${stopwatch.elapsedMilliseconds}ms", tag: "DB-Migration");
  }
}
