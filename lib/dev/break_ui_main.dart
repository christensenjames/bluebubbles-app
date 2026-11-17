// Debug-only break-ui harness. Build with:
//   flutter build linux --debug --no-pub -t lib/dev/break_ui_main.dart
// Run it only with XDG_DATA_HOME pointed at a scratch dir and no network (see lib/dev/break_ui.sh).
//
// The fixture is chosen at launch, never in the app:
//   BB_FIXTURE=demo|worst|one|empty   which dataset to seed (default demo)
//   BB_WINDOW=412x892                 window size (under 600 wide gives the phone layout)
//   BB_THEME=dark|light               default dark
//   BB_OPEN=spam|<fixture chat id>    navigate after the list loads
//   BB_SNACKBAR=delete|delete-thirty|save|spam-error
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:bluebubbles/app/layouts/conversation_list/widgets/header/header_widgets.dart' show goToLikelySpam;
import 'package:bluebubbles/app/layouts/conversation_view/pages/conversation_view.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/dev/break_ui_fixtures.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/main.dart' as app;
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _marker = '.break-ui-fixture';

Future<void> main(List<String> arguments) async {
  if (!kDebugMode) throw StateError('break_ui_main is a debug-only harness');
  final env = Platform.environment;
  final fixture = env['BB_FIXTURE'] ?? 'demo';
  final chats = fixtureChats(fixture);

  // Reseeding wipes the store, so refuse anything that could be James's real data dir.
  final dataHome = env['XDG_DATA_HOME'];
  if (dataHome == null || p.equals(p.normalize(dataHome), p.join(env['HOME'] ?? '', '.local', 'share'))) {
    throw StateError('Set XDG_DATA_HOME to a scratch directory before running the break-ui harness');
  }
  final dir = await getApplicationSupportDirectory();
  if (dir.existsSync() && dir.listSync().isNotEmpty && !File(p.join(dir.path, _marker)).existsSync()) {
    throw StateError('${dir.path} holds data the harness did not create; refusing to reseed it');
  }
  dir.createSync(recursive: true);
  File(p.join(dir.path, _marker)).writeAsStringSync(fixture);
  _writePrefs(dir, env);

  final dbDir = Directory(p.join(dir.path, 'objectbox'));
  if (dbDir.existsSync()) dbDir.deleteSync(recursive: true);
  final store = Store(getObjectBoxModel(), directory: dbDir.path);
  seedFixture(store, chats);
  store.close();
  debugPrint('[break-ui] seeded fixture "$fixture" (${chats.length} chats) into ${dbDir.path}');

  await app.main(arguments);
  unawaited(_afterStartup(env, chats));
}

void _writePrefs(Directory dir, Map<String, String> env) {
  final size = (env['BB_WINDOW'] ?? '1280x768').split('x').map(double.parse).toList();
  final prefs = <String, Object>{
    'migrationCompleted': true,
    'finishedSetup': true,
    'reachedConversationList': true,
    'dbVersion': Database.version,
    // Discard port: nothing answers even if the harness is started without a network namespace.
    'serverAddress': 'http://127.0.0.1:9',
    'skin': Skins.Material.index,
    'adaptive_theme_preferences': jsonEncode({
      'theme_mode': (env['BB_THEME'] == 'light' ? AdaptiveThemeMode.light : AdaptiveThemeMode.dark).index,
      'default_theme_mode': AdaptiveThemeMode.system.index,
    }),
    'titleBarStyle': BBTitleBarStyle.custom.index,
    'tabletMode': true,
    'selected-light': 'Bright White',
    'selected-dark': 'OLED Dark',
    'window-width': size[0],
    'window-height': size[1],
    'window-x': 0.0,
    'window-y': 0.0,
  };
  File(p.join(dir.path, 'shared_preferences.json')).writeAsStringSync(jsonEncode(prefs));
}

Future<void> _afterStartup(Map<String, String> env, List<FixtureChat> chats) async {
  while (!GetIt.I.isRegistered<ChatsService>() || !ChatsSvc.loadedFirstChatBatch.value || Get.context == null) {
    await Future.delayed(const Duration(milliseconds: 250));
  }
  await Future.delayed(const Duration(seconds: 2));

  final open = env['BB_OPEN'];
  if (open == 'spam') {
    goToLikelySpam(Get.context!);
  } else if (open != null) {
    final guid = chats.firstWhere((c) => c.id == open).guid;
    final chat = ChatsSvc.getChatState(guid)!.chat;
    unawaited(NavigationSvc.pushAndRemoveUntil(Get.context!, ConversationView(chat: chat), (route) => route.isFirst));
  }

  final snack = env['BB_SNACKBAR'];
  if (snack != null) {
    await Future.delayed(const Duration(seconds: 2));
    final s = snackbarFixture(snack);
    showSnackbar(
      s.title,
      s.message,
      type: s.error ? SnackbarType.error : SnackbarType.success,
      // Held on screen for the screenshot; every other argument is what the real caller passes.
      durationMs: 600000,
      actionLabel: s.actionLabel,
      onAction: s.actionLabel == null ? null : () {},
    );
  }
  debugPrint('[break-ui] ready');
}
