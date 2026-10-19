import 'package:bluebubbles/app/layouts/settings/widgets/layout/settings_leading_icons.dart';
import 'package:bluebubbles/app/components/bb_switch.dart';
import 'package:bluebubbles/app/layouts/settings/widgets/content/settings_leading_icon.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({
    super.key,
    required this.initialVal,
    required this.onChanged,
    required this.title,
    this.backgroundColor,
    this.subtitle,
    this.isThreeLine = false,
    this.leading,
  });
  final bool initialVal;
  final Function(bool) onChanged;
  final String title;
  final Color? backgroundColor;
  final String? subtitle;
  final bool isThreeLine;
  final SettingsLeadingIcon? leading;

  @override
  Widget build(BuildContext context) {
    final material = context.material;
    final showLeading = leading != null && (!material || SettingsLeadingIcons.shown(context));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onChanged.call(!initialVal),
        splashColor: context.theme.colorScheme.surfaceVariant,
        splashFactory: context.theme.splashFactory,
        child: ListTile(
          mouseCursor: MouseCursor.defer,
          enableFeedback: true,
          minVerticalPadding: material ? 12 : 10,
          horizontalTitleGap: material ? 13 : 10,
          title: Text(
            title,
            style: context.theme.textTheme.bodyLarge!.copyWith(fontWeight: material ? FontWeight.w500 : null),
          ),
          leading: !showLeading
              ? null
              : Padding(
                  padding: material
                      ? EdgeInsets.zero
                      : EdgeInsets.only(bottom: isThreeLine ? 10 : 0.0, right: 5, left: 5),
                  child: leading,
                ),
          trailing: BBSwitch(
            value: initialVal,
            activeColor: material ? null : context.theme.colorScheme.primary.lightenOrDarken(15),
            onChanged: onChanged,
          ),
          subtitle: subtitle != null
              ? Text(
                  subtitle!,
                  style: material
                      ? context.theme.textTheme.bodyMedium!.copyWith(color: context.theme.colorScheme.onSurfaceVariant)
                      : context.theme.textTheme.bodySmall!.copyWith(
                          color: context.theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75), height: 1.5),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
        ),
      ),
    );
  }
}
