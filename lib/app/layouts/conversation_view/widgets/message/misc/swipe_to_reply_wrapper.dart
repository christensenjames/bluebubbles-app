import 'dart:math';

import 'package:bluebubbles/app/state/message_state_scope.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/misc/slide_to_reply.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reply/reply_bubble.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/models/models.dart' show MessageReplyContext;
import 'package:bluebubbles/services/backend/settings/settings_service.dart';
import 'package:bluebubbles/services/ui/chat/conversation_view_controller.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// Handles swipe-to-reply gesture detection and haptic feedback
/// Extracted from MessageHolder to improve readability and reusability
class SwipeToReplyWrapper extends StatefulWidget {
  const SwipeToReplyWrapper({
    super.key,
    required this.enabled,
    required this.partIndex,
    required this.replyOffset,
    required this.cvController,
    required this.child,
  });

  final bool enabled;
  final int partIndex;
  final RxDouble replyOffset;
  final ConversationViewController cvController;
  final Widget child;

  @override
  State<SwipeToReplyWrapper> createState() => _SwipeToReplyWrapperState();
}

class _SwipeToReplyWrapperState extends State<SwipeToReplyWrapper> {
  // Same fling threshold as Dismissible.
  static const double _flingVelocity = 700;

  bool gaveHapticFeedback = false;
  double _dragDistance = 0;

  void _handleHapticFeedback() {
    if (!gaveHapticFeedback && widget.replyOffset.value.abs() >= SlideToReply.replyThreshold) {
      HapticFeedback.lightImpact();
      gaveHapticFeedback = true;
    } else if (widget.replyOffset.value.abs() < SlideToReply.replyThreshold) {
      gaveHapticFeedback = false;
    }
  }

  // Tracks the finger 1:1 up to the trigger point, then resists, approaching threshold + threshold / 2.
  static double _rubberBand(double distance) {
    const threshold = SlideToReply.replyThreshold;
    if (distance <= threshold) return distance;
    const limit = threshold / 2;
    final excess = distance - threshold;
    return threshold + limit * (1 - 1 / (excess * 0.55 / limit + 1));
  }

  void _settle() {
    gaveHapticFeedback = false;
    _dragDistance = 0;
    widget.replyOffset.value = 0;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return widget.child;
    }

    final message = MessageStateScope.messageOf(context);
    // iOS skin: right always replies, so left stays free for the message list's timestamp reveal.
    final replySign = SettingsSvc.settings.skin.value == Skins.iOS || !message.isFromMe! ? 1.0 : -1.0;
    return RawGestureDetector(
      behavior: HitTestBehavior.deferToChild,
      gestures: {
        _ReplyDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<_ReplyDragGestureRecognizer>(
          () => _ReplyDragGestureRecognizer(debugOwner: this),
          (recognizer) => recognizer
            ..replySign = replySign
            ..onUpdate = (details) {
              if (ReplyScope.maybeOf(context) != null) return;

              _dragDistance = max(0.0, _dragDistance + details.delta.dx * replySign);
              widget.replyOffset.value = _rubberBand(_dragDistance) * replySign;
              _handleHapticFeedback();
            }
            ..onEnd = (details) {
              if (ReplyScope.maybeOf(context) != null) return;

              final flung = (details.primaryVelocity ?? 0) * replySign >= _flingVelocity;
              if (_dragDistance >= SlideToReply.replyThreshold || flung) {
                if (!gaveHapticFeedback) HapticFeedback.lightImpact();
                widget.cvController.replyToMessage = MessageReplyContext(message, widget.partIndex);
              }
              _settle();
            }
            ..onCancel = () {
              if (ReplyScope.maybeOf(context) != null) return;
              _settle();
            },
        ),
      },
      child: widget.child,
    );
  }
}

/// Claims the gesture arena only for drags toward the reply side, so a drag the other way reaches ancestors.
class _ReplyDragGestureRecognizer extends HorizontalDragGestureRecognizer {
  _ReplyDragGestureRecognizer({super.debugOwner});

  /// 1 when the reply side is to the right, -1 when it is to the left.
  double replySign = 1;

  @override
  bool hasSufficientGlobalDistanceToAccept(PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) {
    return globalDistanceMoved * replySign > computeHitSlop(pointerDeviceKind, gestureSettings);
  }
}
