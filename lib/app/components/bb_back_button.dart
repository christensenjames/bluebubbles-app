import 'package:flutter/material.dart';
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
    return IconButton(
      tooltip: 'Back',
      icon: icon,
      iconSize: iconSize,
      style: style,
      onPressed: () => _pop(context),
    );
  }
}
