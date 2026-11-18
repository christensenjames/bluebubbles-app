import 'package:bluebubbles/database/migrations/migration_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  setUpAll(registerTestLogger);

  late List<int> migrated;
  late List<int> saved;

  setUp(() {
    migrated = [];
    saved = [];
  });

  Future<void> run(int from, int to, {int? failAt}) => MigrationRunner.run(
        from: from,
        to: to,
        migrate: (version) async {
          migrated.add(version);
          if (version == failAt) throw StateError('step $version failed');
        },
        saveVersion: (version) async => saved.add(version),
      );

  test('runs each step after the stored version in order and saves each version', () async {
    await run(7, 10);

    expect(migrated, [8, 9, 10]);
    expect(saved, [8, 9, 10]);
  });

  test('a failing step stops the run and leaves the version before it saved', () async {
    await expectLater(run(1, 5, failAt: 3), throwsStateError);

    expect(migrated, [2, 3]);
    expect(saved, [2]);
  });

  test('the next run resumes at the step that failed', () async {
    await expectLater(run(1, 5, failAt: 3), throwsStateError);
    final lastSaved = saved.last;
    migrated.clear();
    saved.clear();

    await run(lastSaved, 5);

    expect(migrated, [3, 4, 5]);
    expect(saved, [3, 4, 5]);
  });

  test('an up-to-date database runs no steps', () async {
    await run(10, 10);

    expect(migrated, isEmpty);
    expect(saved, isEmpty);
  });
}
