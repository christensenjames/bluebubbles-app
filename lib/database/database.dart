import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bluebubbles/app/layouts/conversation_view/widgets/text_field/buttons/text_field_button.dart';
import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/helpers/backend/startup_tasks.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/backend/actions/image_actions.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/database/migrations/chat_latest_message_migration.dart';
import 'package:bluebubbles/database/migrations/message_handle_id_migration.dart';
import 'package:bluebubbles/database/migrations/message_handle_relationship_migration.dart';
import 'package:bluebubbles/database/migrations/migration_runner.dart';
import 'package:bluebubbles/database/migrations/preview_icon_migration.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:io/io.dart';
import 'package:path/path.dart';

class Database {
  static int version = 11;

  /// Bump this whenever preset theme definitions change (colors, font sizes,
  /// etc.) to force existing installs to re-seed preset themes on next launch.
  static int themesVersion = 6;

  static late final Store store;
  static late final Box<Attachment> attachments;
  static late final Box<Chat> chats;
  static late final Box<ContactV2> contactsV2;
  static late final Box<CustomGroup> customGroups;
  static late final Box<FCMData> fcmData;
  static late final Box<Handle> handles;
  static late final Box<Message> messages;
  static late final Box<ThemeStruct> themes;
  static late final Box<ThemeEntry> themeEntries;

  // ignore: deprecated_member_use_from_same_package
  static late final Box<ThemeObject> themeObjects;

  static String get appDocPath => FilesystemSvc.appDocDir.path;

  static final Completer<void> initComplete = Completer();

  static Future<void> init() async {
    // Web doesn't use a database currently, so do not do anything
    if (kIsWeb) return;

    if (!kIsDesktop) {
      await _initDatabaseMobile();
    } else {
      await _initDatabaseDesktop();
    }

    try {
      bindBoxes();

      // Wait for SettingsService to be fully initialized before accessing settings.
      // This _shouldn't_ be needed, but we're going to do it just in case...
      bool setupFinished = false;
      if (GetIt.I.isRegistered<SettingsService>()) {
        await SettingsSvc.initCompleted.future;
        setupFinished = SettingsSvc.settings.finishedSetup.value;
      }

      bool setupFinished2 = PrefsSvc.database.getFinishedSetup();
      Logger.info(
          "Database init: SettingsSvc.finishedSetup = $setupFinished, PrefsSvc.finishedSetup = $setupFinished2");

      // Setup only ever runs on main, so only main may act on an unfinished one.
      if (!setupFinished && !isIsolate) {
        Logger.warn("Clearing database because setup is not finished...");

        Database.attachments.removeAll();
        Database.chats.removeAll();
        Database.contactsV2.removeAll();
        Database.fcmData.removeAll();
        Database.handles.removeAll();
        Database.messages.removeAll();
        Database.themes.removeAll();
        Database.themeEntries.removeAll();
        themeObjects.removeAll();
      }
    } catch (e, s) {
      Logger.error("Failed to setup ObjectBox boxes!", error: e, trace: s);
    }

    try {
      await _performDatabaseMigrations();
      await PrefsSvc.database.setDbVersion(version);
    } catch (e, s) {
      Logger.error("Failed to perform database migrations!", error: e, trace: s);
    }

    await seedThemes();

    initComplete.complete();
  }

  static void bindBoxes() {
    Database.attachments = store.box<Attachment>();
    Database.chats = store.box<Chat>();
    Database.contactsV2 = store.box<ContactV2>();
    Database.customGroups = store.box<CustomGroup>();
    Database.fcmData = store.box<FCMData>();
    Database.handles = store.box<Handle>();
    Database.messages = store.box<Message>();
    Database.themes = store.box<ThemeStruct>();
    Database.themeEntries = store.box<ThemeEntry>();
    // ignore: deprecated_member_use_from_same_package
    themeObjects = store.box<ThemeObject>();
  }

  static Future<void> waitForInit() async {
    await initComplete.future;
  }

  static Future<void> _initDatabaseMobile({bool? storeOpenStatus, ByteData? storeReference}) async {
    if (storeReference != null) {
      Logger.info("Attaching to existing ObjectBox store via reference");
      store = Store.fromReference(getObjectBoxModel(), storeReference);
      return;
    }
    Directory objectBoxDirectory = Directory(join(FilesystemSvc.appDocDir.path, 'objectbox'));
    final isStoreOpen = storeOpenStatus ?? Store.isOpen(objectBoxDirectory.path);

    try {
      if (isStoreOpen) {
        Logger.info("Attempting to attach to an existing ObjectBox store...");
        store = Store.attach(getObjectBoxModel(), objectBoxDirectory.path);
        Logger.info("Successfully attached to an existing ObjectBox store");
      } else {
        Logger.info("Opening new ObjectBox store from path: ${objectBoxDirectory.path}");
        store = await openStore(directory: objectBoxDirectory.path);
      }
    } catch (e, s) {
      Logger.error("Failed to open ObjectBox store!", error: e, trace: s);

      if (e.toString().contains("another store is still open using the same path")) {
        Logger.info("Retrying to attach to an existing ObjectBox store");
        await _initDatabaseMobile(storeOpenStatus: true);
      }
    }
  }

  static Future<void> _initDatabaseDesktop({ByteData? storeReference}) async {
    if (storeReference != null) {
      Logger.info("Attaching to existing ObjectBox store via reference");
      store = Store.fromReference(getObjectBoxModel(), storeReference);
      return;
    }
    Directory objectBoxDirectory = Directory(join(FilesystemSvc.appDocDir.path, 'objectbox'));

    try {
      objectBoxDirectory.createSync(recursive: true);
      final customPath = PrefsSvc.database.getCustomPath();
      if (PrefsSvc.database.shouldUseCustomPath() && customPath != null) {
        Directory oldCustom = Directory(join(customPath, 'objectbox'));
        if (oldCustom.existsSync()) {
          Logger.info("Detected prior use of custom path option. Migrating...");
          await copyPath(oldCustom.path, objectBoxDirectory.path);
        }
        await PrefsSvc.database.clearCustomPathConfig();
      }

      Logger.info("Opening ObjectBox store from path: ${objectBoxDirectory.path}");
      store = await openStore(directory: objectBoxDirectory.path);
    } catch (e) {
      if (e.toString().contains("another store is still open using the same path")) {
        Logger.debug("Retrying to attach to an existing ObjectBox store");
        store = Store.attach(getObjectBoxModel(), objectBoxDirectory.path);
      }
    }
  }

  static Future<void> _performDatabaseMigrations() async {
    await MigrationRunner.run(
      from: PrefsSvc.database.getDbVersion() ?? (SettingsSvc.settings.finishedSetup.value ? 1 : Database.version),
      to: Database.version,
      migrate: _migrateTo,
      saveVersion: PrefsSvc.database.setDbVersion,
    );
  }

  static Future<void> _migrateTo(int nextVersion) async {
    await StartupTasks.setSplashStatus("Updating database ($nextVersion of ${Database.version})...");

    switch (nextVersion) {
      // Version 2 changed handleId to match the server side ROWID, rather than client side ROWID
      case 2:
        MessageHandleIdMigration.migrate();
        break;

      // Version 3 modifies chat typing indicators and read receipts values to follow global setting initially
      case 3:
        final chats = Database.chats.getAll();
        final papi = SettingsSvc.settings.enablePrivateAPI.value;
        final typeGlobal = SettingsSvc.settings.privateSendTypingIndicators.value;
        final readGlobal = SettingsSvc.settings.privateMarkChatAsRead.value;
        for (Chat c in chats) {
          if (papi && readGlobal && !(c.autoSendReadReceipts ?? true)) {
            // dont do anything
          } else {
            c.autoSendReadReceipts = null;
          }
          if (papi && typeGlobal && !(c.autoSendTypingIndicators ?? true)) {
            // dont do anything
          } else {
            c.autoSendTypingIndicators = null;
          }
        }
        Database.chats.putMany(chats);
        break;

      // Version 4 saves FCM Data to the shared preferences for use in Tasker integration
      case 4:
        SettingsSvc.loadFcmDataFromDatabase();
        SettingsSvc.fcmData.save();
        break;

      case 5:
        // Find the Bright White theme and reset it back to the default (new colors)
        final brightWhite = Database.themes.query(ThemeStruct_.name.equals("Bright White")).build().findFirst();
        if (brightWhite != null) {
          brightWhite.data = ThemesService.whiteLightTheme;
          Database.themes.put(brightWhite, mode: PutMode.update);
        }

        // Find the OLED theme and reset it back to the default (new colors)
        final oled = Database.themes.query(ThemeStruct_.name.equals("OLED Dark")).build().findFirst();
        if (oled != null) {
          oled.data = ThemesService.oledDarkTheme;
          Database.themes.put(oled, mode: PutMode.update);
        }
        break;

      // Version 6: Migrate Message.handle from embedded object to ToOne relationship (Phase 2)
      case 6:
        Logger.info("Executing Message-Handle relationship migration (Phase 2)...", tag: "DB-Migration");
        await MessageHandleRelationshipMigration.migrate();
        break;

      // Version 7: Remove V1 Contact entity (we don't need to do anything.)
      // We removed the code, so it's unused, but it'll remain in the database.
      case 7:
        break;

      // Version 8: Backfill Chat.dbLatestMessage (ToOne<Message>) and
      // dbOnlyLatestMessageDate from each chat's most recent message.
      case 8:
        Logger.info("Executing chat latest message backfill...", tag: "DB-Migration");
        await ChatLatestMessageMigration.migrate();
        break;

      // Version 9: move legacy Monet overlay users to the new Material You
      // presets so selected theme becomes the single source of truth.
      case 9:
        final monetModeRaw = PrefsSvc.admin.get('monetTheming') as int?;
        if (monetModeRaw == 1 || monetModeRaw == 2) {
          await PrefsSvc.theme.setSelectedThemes(
            lightTheme: ThemesService.materialYouLightName,
            darkTheme: ThemesService.materialYouDarkName,
          );
        }
        await PrefsSvc.admin.remove('monetTheming');
        break;

      // Version 10: favicons cached before convertIcoToPng passed `singleFrame: true` are APNGs that cycle
      // through every .ico resolution, and the cache is never re-fetched, so flatten them in place.
      case 10:
        final hashes = PreviewIconMigration.hashes();
        for (final hash in hashes) {
          final path = FilesystemSvc.urlPreviewImagePath(hash);
          if (File(path).existsSync()) ImageActions.flattenAnimatedPng(path);
        }
        break;

      case 11:
        final buttons = SettingsSvc.settings.textFieldButtons;
        if (!buttons.contains(TextFieldButton.Schedule)) {
          buttons.add(TextFieldButton.Schedule);
          await PrefsSvc.admin.setString('textFieldButtons', jsonEncode(buttons.map((button) => button.name).toList()));
        }
        break;
    }

    // Back to the spinner
    await StartupTasks.setSplashProgress(-1);
  }

  static Future<void> seedThemes() async {
    try {
      final isFirstRun = Database.themes.isEmpty();
      final storedThemesVersion = PrefsSvc.database.getThemesVersion();
      final needsReseed = isFirstRun || storedThemesVersion < Database.themesVersion;
      if (isFirstRun) {
        await PrefsSvc.theme.setSelectedThemes(
          darkTheme: "OLED Dark",
          lightTheme: "Bright White",
        );
      }
      if (needsReseed) {
        for (final preset in ThemesService.defaultThemes) {
          final existing = ThemeStruct.findOne(preset.name);
          if (existing != null) preset.id = existing.id;
          Database.themes.put(preset);
        }
        await PrefsSvc.database.setThemesVersion(Database.themesVersion);
      }
    } catch (e, s) {
      Logger.error("Failed to seed themes!", error: e, trace: s);
    }
  }

  /// Wrapper for store.runInTransaction
  static R runInTransaction<R>(TxMode mode, R Function() fn) {
    return store.runInTransaction(mode, fn);
  }

  /// Wipes every ObjectBox box that's actually populated, including theme entries.
  /// Used for a full app reset — for a messaging-only wipe that preserves
  /// settings/themes/fcmData, use [resetMessagingData].
  ///
  /// Note: scheduled messages are not stored locally — they live server-side and
  /// are fetched via the API (see `ScheduledMessagesMixin`), so there's nothing to
  /// clear here for them.
  static void reset() {
    Database.attachments.removeAll();
    Database.chats.removeAll();
    Database.fcmData.removeAll();
    Database.contactsV2.removeAll();
    Database.handles.removeAll();
    Database.messages.removeAll();
    Database.themes.removeAll();
    Database.themeEntries.removeAll();
    Database.customGroups.removeAll();
  }

  /// Wipes messaging-scoped data: attachments, chats, contactsV2, handles, messages, and custom groups.
  /// Leaves settings, themes, and fcmData untouched.
  static void resetMessagingData() {
    Database.runInTransaction(TxMode.write, () {
      Database.attachments.removeAll();
      Database.chats.removeAll();
      Database.contactsV2.removeAll();
      Database.handles.removeAll();
      Database.messages.removeAll();
      Database.customGroups.removeAll();
    });
  }
}
