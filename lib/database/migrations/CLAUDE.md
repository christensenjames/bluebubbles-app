# database/migrations/ — ObjectBox Schema Migrations

Contains migration scripts that run when the database version is incremented.

## Files

| File | Purpose |
|------|---------|
| `message_handle_relationship_migration.dart` | Migrates legacy message→handle relationships to the new N:M `ToMany` schema |
| `chat_latest_message_migration.dart` | Backfills `Chat.dbLatestMessage` / `dbOnlyLatestMessageDate` |
| `message_handle_id_migration.dart` | Version 2: remaps incoming messages' `handleId` from the local handle id to the server ROWID |
| `preview_icon_migration.dart` | Version 10: collects cached link-preview icon hashes, skipping unparseable metadata |
| `migration_runner.dart` | `MigrationRunner.run`: steps from the stored version to `Database.version`, saving each version after its step |

Tests for these steps live in `test/database/migrations_test.dart`, and for the runner in
`test/database/migration_runner_test.dart`; a new step should get one there.

## How Migrations Work
1. `database.dart` stores `Database.version`
2. On startup, `MigrationRunner.run` calls `Database._migrateTo` for each version after the stored one, whose `switch`
   runs that version's step:
   ```dart
   switch (nextVersion) {
     case N: MyMigration.migrate(); break;
   }
   ```
3. The stored version is saved after each step. A step that throws stops the run; `Database.init` logs the error and
   startup continues, and the failed step runs again on the next launch.

## Adding a Migration
1. Create `my_migration.dart` in this directory
2. Register it in the version switch in `lib/database/database.dart`
3. Bump `Database.version`
4. Run `dart run build_runner build` if `@Entity` annotations changed

## Rules
- Migrations are one-shot and irreversible — always test with a real device DB before shipping
- Never edit `lib/generated/objectbox.g.dart` directly
- Add `@Property(uid: ...)` to new entity fields to avoid schema conflicts

## Related
- Database init: `lib/database/database.dart`
- Entity definitions: `../io/CLAUDE.md`
