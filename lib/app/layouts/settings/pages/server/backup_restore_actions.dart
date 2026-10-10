import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:universal_io/io.dart';
import 'package:window_manager/window_manager.dart';

class BackupRestoreActions {
  static Future<void> applyRestoredSettings() async {
    HttpSvc.updateTimeouts();
    Logger.currentLevel = SettingsSvc.settings.logLevel.value;
    await SettingsSvc.updateDisplayMode();
    if (!kIsDesktop) return;
    await windowManager.setPreventClose(SettingsSvc.settings.closeToTray.value);
    SettingsSvc.settings.launchAtStartup.value = await SettingsSvc.setupLaunchAtStartup(
        SettingsSvc.settings.launchAtStartup.value, SettingsSvc.settings.launchAtStartupMinimized.value);
    if (Platform.isLinux) {
      await windowManager.setTitleBarStyle(SettingsSvc.settings.titleBarStyle.value == BBTitleBarStyle.native
          ? TitleBarStyle.normal
          : TitleBarStyle.hidden);
    }
  }

  static Future<bool> fetchBackups({
    required List<Map<String, dynamic>> settings,
    required List<Map<String, dynamic>> themes,
  }) async {
    final settingsRes = await HttpSvc.backup.getSettings().catchError((_) {
      return Response(requestOptions: RequestOptions(path: ''));
    });
    if (settingsRes.statusCode != 200 || settingsRes.data['data'] == null) {
      return false;
    }

    settings
      ..clear()
      ..addAll(settingsRes.data['data'].cast<Map<String, dynamic>>());
    settings.sort(
      (a, b) => DateTime.fromMillisecondsSinceEpoch(b['timestamp'] ?? 0)
          .compareTo(DateTime.fromMillisecondsSinceEpoch(a['timestamp'] ?? 0)),
    );

    final themesRes = await HttpSvc.backup.getTheme().catchError((_) {
      return Response(requestOptions: RequestOptions(path: ''));
    });
    if (themesRes.statusCode == 200 && themesRes.data['data'] != null) {
      themes
        ..clear()
        ..addAll(themesRes.data['data'].cast<Map<String, dynamic>>());
    }
    return true;
  }

  static void deleteSettings({
    required List<Map<String, dynamic>> settings,
    required String name,
  }) {
    settings.removeWhere((element) => element["name"] == name);
    HttpSvc.backup.deleteSettings(name);
  }

  static void deleteTheme({
    required List<Map<String, dynamic>> themes,
    required String name,
  }) {
    themes.removeWhere((element) => element["name"] == name);
    HttpSvc.backup.deleteTheme(themeBackupKey(name));
  }

  /// The server stores a theme backup under its name, rejecting names over 50 UTF-16 code units.
  static String themeBackupKey(String name) {
    final key = StringBuffer();
    for (final grapheme in name.characters) {
      if (key.length + grapheme.length > 50) break;
      key.write(grapheme);
    }
    return key.toString();
  }

  static Future<String> defaultDeviceName() async {
    final deviceInfo = DeviceInfoPlugin();

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      return "Android (${androidInfo.model})";
    } else if (kIsWeb) {
      final webInfo = await deviceInfo.webBrowserInfo;
      return "Web (${webInfo.browserName.name})";
    } else if (Platform.isWindows) {
      final windowsInfo = await deviceInfo.windowsInfo;
      return "Windows (${windowsInfo.computerName})";
    } else if (Platform.isLinux) {
      final linuxInfo = await deviceInfo.linuxInfo;
      return "Linux (${linuxInfo.name})";
    }

    return "Unknown Device";
  }
}
