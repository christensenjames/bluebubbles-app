import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';

class SettingsHeader extends StatelessWidget {
  final TextStyle? iosSubtitle;
  final TextStyle? materialSubtitle;
  final String text;
  final double? height;

  const SettingsHeader({
    super.key,
    required this.iosSubtitle,
    required this.materialSubtitle,
    required this.text,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final skin = SettingsSvc.settings.skin.value;
    if (skin == Skins.Samsung) return const SizedBox(height: 10);
    final iOS = skin == Skins.iOS;
    final material = skin == Skins.Material;
    return Container(
      height: height ?? (iOS ? 60 : (material ? 52 : 40)),
      alignment: Alignment.bottomLeft,
      color: Colors.transparent,
      child: Padding(
        // 12 + the section's 4 dp margin puts the label 16 dp above its group on Material
        padding: EdgeInsets.only(
          bottom: material ? 12.0 : 8.0,
          left: iOS ? 30 : (material ? 24 : 15),
        ),
        child: Text(text.psCapitalize, style: iOS ? iosSubtitle : materialSubtitle),
      ),
    );
  }
}
