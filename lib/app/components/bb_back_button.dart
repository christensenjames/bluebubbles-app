import 'package:bluebubbles/helpers/helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gesture_x_detector/gesture_x_detector.dart';
import 'package:get/get.dart';

class BBBackButton extends StatelessWidget {
  final Widget icon;
  final double? iconSize;
  final ButtonStyle? style;
  final bool Function()? onPressed;

  const BBBackButton({
    super.key,
    required this.icon,
    this.iconSize,
    this.style,
    this.onPressed,
  });

  void _pop(BuildContext context) {
    if (onPressed?.call() ?? false) return;
    if (Get.isSnackbarOpen) Get.closeAllSnackbars();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return XGestureDetector(
      supportTouch: true,
      behavior: HitTestBehavior.opaque,
      onTap: kIsDesktop ? (_) => _pop(context) : null,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: kIsDesktop
            ? (_, event) {
                final key = event.logicalKey;
                if (key != LogicalKeyboardKey.enter &&
                    key != LogicalKeyboardKey.numpadEnter &&
                    key != LogicalKeyboardKey.space) {
                  return KeyEventResult.ignored;
                }
                if (event is KeyUpEvent) _pop(context);
                return KeyEventResult.handled;
              }
            : null,
        child: IconButton(
          tooltip: 'Back',
          icon: icon,
          iconSize: iconSize,
          style: style,
          // Keep ink hit testing active; desktop clicks use XGestureDetector under the draggable titlebar.
          onPressed: () {
            if (!kIsDesktop) _pop(context);
          },
        ),
      ),
    );
  }
}
