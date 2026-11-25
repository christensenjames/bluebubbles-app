import 'package:bluebubbles/app/components/m3e/m3e_motion.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class SendButton extends StatefulWidget {
  const SendButton({
    super.key,
    required this.onLongPress,
    required this.sendMessage,
    this.visible = true,
    this.enabled = true,
    this.materialComposer = false,
    this.scheduled = false,
  });

  final Function() onLongPress;
  final Function() sendMessage;
  final bool visible;
  final bool enabled;
  final bool materialComposer;
  final bool scheduled;

  @override
  SendButtonState createState() => SendButtonState();
}

class SendButtonState extends State<SendButton> with SingleTickerProviderStateMixin, ThemeHelpers {
  // The fill counts down the real send delay, so it keeps running under reduced motion; `preserve` stops
  // the OS flag from cutting the delay itself to 5%.
  late final controller = AnimationController(
      vsync: this,
      duration: Duration(seconds: SettingsSvc.settings.sendDelay.value),
      animationBehavior: AnimationBehavior.preserve);

  // Colors cached here and refreshed in didChangeDependencies so they update
  // when an inherited Theme changes (e.g. per-chat adaptive theme loading).
  late Color _iosBaseColor;
  late Color _materialBaseColor;
  late Color _errorColor;
  late Color _iosOnPrimary;
  late Color _materialIconColor;
  late Color _onError;

  Color get baseColor => iOS ? _iosBaseColor : _materialBaseColor;

  @override
  void initState() {
    super.initState();
    controller.addListener(() {
      if (controller.isCompleted) {
        controller.reset();
        widget.sendMessage.call();
      }
    });
  }

  @override
  void didUpdateWidget(SendButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.visible && !widget.visible) || (oldWidget.enabled && !widget.enabled)) controller.reset();
  }

  void _handleLongPress() {
    if (controller.isAnimating) {
      controller.reset();
    } else {
      widget.onLongPress.call();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _iosBaseColor = context.theme.colorScheme.primary;
    _materialBaseColor = context.theme.colorScheme.surfaceContainerHighest;
    _errorColor = context.theme.colorScheme.error;
    _iosOnPrimary = context.theme.colorScheme.onPrimary;
    _materialIconColor =
        ThemeSvc.isAnyMaterialYouSelected ? context.theme.colorScheme.onPrimary : context.theme.colorScheme.secondary;
    _onError = context.theme.colorScheme.onError;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double side = widget.materialComposer ? 54 : material ? 40 : 32;
    return GestureDetector(
      onSecondaryTap: widget.enabled ? _handleLongPress : null,
      child: TextButton(
        style: TextButton.styleFrom(
          backgroundColor: iOS ? _iosBaseColor : null,
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(0),
          maximumSize: Size.square(side),
          minimumSize: Size.square(side),
          tapTargetSize: MaterialTapTargetSize.padded,
        ),
        onPressed: widget.enabled ? onSendPressed : null,
        onLongPress: widget.enabled ? _handleLongPress : null,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            return _SendButtonIcon(
              animationValue: controller.value,
              baseColor: baseColor,
              errorColor: _errorColor,
              iosOnPrimary: _iosOnPrimary,
              materialSecondary: _materialIconColor,
              onError: _onError,
              enabled: widget.enabled,
              side: side,
              materialComposer: widget.materialComposer,
              scheduled: widget.scheduled,
            );
          },
        ),
      ),
    );
  }

  void onSendPressed() {
    if (!widget.enabled) return;
    if (controller.isAnimating) {
      controller.reset();
    } else if (SettingsSvc.settings.sendDelay.value != 0) {
      controller.forward();
    } else {
      HapticFeedback.lightImpact();
      widget.sendMessage.call();
    }
  }
}

/// Extracted animated icon to reduce rebuild scope
class _SendButtonIcon extends StatelessWidget {
  const _SendButtonIcon({
    required this.animationValue,
    required this.baseColor,
    required this.errorColor,
    required this.iosOnPrimary,
    required this.materialSecondary,
    required this.onError,
    required this.enabled,
    required this.side,
    required this.materialComposer,
    required this.scheduled,
  });

  final double animationValue;
  final Color baseColor;
  final Color errorColor;
  final Color iosOnPrimary;
  final Color materialSecondary;
  final Color onError;
  final bool enabled;
  final double side;
  final bool materialComposer;
  final bool scheduled;

  static Widget _swapTransition(Widget child, Animation<double> animation) {
    final scaled = ScaleTransition(scale: Tween(begin: 0.5, end: 1.0).animate(animation), child: child);
    return FadeTransition(
      opacity: animation,
      child: child.key == const ValueKey(true)
          ? RotationTransition(turns: Tween(begin: -1 / 12, end: 0.0).animate(animation), child: scaled)
          : scaled,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final isIOS = SettingsSvc.settings.skin.value == Skins.iOS;
      final isMaterial = SettingsSvc.settings.skin.value == Skins.Material;
      final isAnimating = animationValue != 0;
      final filled = isMaterial && !isAnimating;
      final color = isAnimating
          ? onError
          : isIOS
              ? iosOnPrimary
              : enabled == filled
                  ? context.theme.colorScheme.onPrimary
                  : materialComposer
                      ? context.theme.colorScheme.onSurface.withValues(alpha: 0.38)
                      : materialSecondary;
      final size = materialComposer ? 24.0 : isIOS || isAnimating || filled ? 20.0 : 28.0;

      return Container(
        constraints: BoxConstraints.tight(Size.square(side)),
        decoration: BoxDecoration(
          shape: isIOS || filled || materialComposer ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: isIOS || filled || materialComposer ? null : BorderRadius.circular(10),
          color: filled
              ? context.theme.colorScheme.primary.withValues(alpha: materialComposer && !enabled ? 0.38 : 1)
              : null,
          gradient: isIOS || isAnimating
              ? LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [baseColor, baseColor, errorColor, errorColor],
                  stops: [0.0, 1 - animationValue, 1 - animationValue, 1.0],
                )
              : null,
        ),
        alignment: Alignment.center,
        child: isAnimating
            ? Icon(isIOS ? CupertinoIcons.xmark : Icons.close, semanticLabel: "Cancel send", color: color, size: size)
            : AnimatedSwitcher(
                duration: M3EMotion.spatialFast.durationOf(context),
                switchInCurve: M3EMotion.spatialFast.curve,
                switchOutCurve: M3EMotion.spatialFast.curve.flipped,
                transitionBuilder: _swapTransition,
                child: scheduled
                    // The glyph's ink box spans font units 64–469 × 43–427 of 512, low and right of center.
                    ? FractionalTranslation(
                        key: const ValueKey(true),
                        translation: const Offset(-10.5 / 512, -21 / 512),
                        child:
                            Icon(Icons.schedule_send_outlined, semanticLabel: "Schedule send", color: color, size: size),
                      )
                    : Icon(isIOS ? CupertinoIcons.arrow_up : Icons.send_outlined,
                        key: const ValueKey(false), semanticLabel: "Send", color: color, size: size),
              ),
      );
    });
  }
}
