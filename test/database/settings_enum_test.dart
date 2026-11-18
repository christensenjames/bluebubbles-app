import 'dart:convert';

import 'package:bluebubbles/database/global/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const keys = [
    'materialRightAction',
    'materialLeftAction',
    'securityLevel',
    'skin',
    'theme',
    'fullscreenViewerSwipeDir',
    'titleBarStyle',
    'logLevel',
  ];

  test('indexed preferences survive a JSON round trip', () {
    final defaults = Settings().toMap();
    final values = {for (final key in keys) key: defaults[key] == 0 ? 1 : 0};
    final restored = Settings.fromMap(jsonDecode(jsonEncode(values)) as Map<String, dynamic>).toMap();
    for (final key in keys) {
      expect(restored[key], values[key], reason: key);
    }
  });

  test('invalid indexes preserve defaults and do not stop later preferences', () {
    final defaults = Settings().toMap();
    for (final key in keys) {
      for (final invalid in [-1, 999999, '1', 1.5, null]) {
        final restored = Settings.fromMap({key: invalid, 'replaceEmoticonsWithEmoji': true}).toMap();
        expect(restored[key], defaults[key], reason: '$key: $invalid');
        expect(restored['replaceEmoticonsWithEmoji'], true, reason: '$key: $invalid');
      }
    }
  });

  test('legacy title bar fallback applies when the new index is missing', () {
    final native = Settings.fromMap({'useCustomTitleBar': false}).toMap()['titleBarStyle'];
    final defaults = Settings().toMap()['titleBarStyle'];
    expect(native, isNot(defaults));
    expect(Settings.fromMap({'titleBarStyle': null, 'useCustomTitleBar': false}).toMap()['titleBarStyle'], native);
    expect(Settings.fromMap({'titleBarStyle': 999999, 'useCustomTitleBar': false}).toMap()['titleBarStyle'], defaults);
  });
}
