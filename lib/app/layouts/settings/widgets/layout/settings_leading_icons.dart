import 'package:flutter/widgets.dart';

/// Opts a settings list into showing row leading icons on the Material skin, where
/// [SettingsTile] and [SettingsSwitch] otherwise drop them. Other skins ignore it.
class SettingsLeadingIcons extends InheritedWidget {
  const SettingsLeadingIcons({super.key, required this.show, required super.child});

  final bool show;

  static bool shown(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SettingsLeadingIcons>()?.show ?? false;

  @override
  bool updateShouldNotify(SettingsLeadingIcons oldWidget) => show != oldWidget.show;
}
