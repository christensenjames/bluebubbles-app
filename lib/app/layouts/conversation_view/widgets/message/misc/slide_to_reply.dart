import 'dart:math';

import 'package:bluebubbles/app/components/m3e/m3e_motion.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/backend/settings/settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SlideToReply extends StatelessWidget {
  const SlideToReply({super.key, required this.width, required this.isFromMe});

  final double width;
  final bool isFromMe;
  static const double replyThreshold = 40;

  @override
  Widget build(BuildContext context) {
    final duration = width == 0 ? M3EMotion.spatialFast.durationOf(context) : Duration.zero;
    final curve = M3EMotion.spatialFast.curve;
    // Past the trigger the indicator stops growing and drifts outward with the swipe's rubber band instead.
    final gap = width == 0 ? 0.0 : 10.0 + max(0.0, width - replyThreshold);
    return AnimatedPadding(
      duration: duration,
      curve: curve,
      padding: EdgeInsets.only(left: isFromMe ? 0 : gap, right: isFromMe ? gap : 0),
      child: AnimatedContainer(
        duration: duration,
        curve: curve,
        width: min(replyThreshold, width) * 0.8,
        height: min(replyThreshold, width) * 0.8,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.all(
            Radius.circular(
              min(replyThreshold, width) * 0.4,
            ),
          ),
          color: context.theme.colorScheme.surfaceContainerHighest,
        ),
        child: AnimatedSize(
          duration: duration,
          curve: curve,
          child: Offstage(
            offstage: kIsWeb && width == 0,
            child: Icon(
              SettingsSvc.settings.skin.value == Skins.iOS ? CupertinoIcons.reply : Icons.reply,
              size: min(replyThreshold, width) * (width >= replyThreshold ? 0.5 : 0.4),
              color: context.theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
