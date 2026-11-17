import 'package:bluebubbles/app/components/m3e/m3e_motion.dart';
import 'package:bluebubbles/app/layouts/conversation_view/pages/handlers/message_list_animation_config.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:flutter/material.dart';

/// Orchestrates message animations when they're added to the list.
///
/// Responsibilities:
/// - Track which messages are currently animating
/// - Apply appropriate animation based on message type (sent vs received)
/// - Build animated widgets with size/scale/fade transitions
/// - Clear animation flags when animations complete
class MessageAnimationOrchestrator {
  /// Track GUIDs of messages currently being animated
  final Set<String> animatingMessageGuids = {};

  /// Check if a message should be animated
  bool isMessageAnimating(Message message) {
    return message.guid != null && animatingMessageGuids.contains(message.guid!);
  }

  /// Mark a message as animating
  void markAnimating(Message message) {
    if (message.guid != null) {
      animatingMessageGuids.add(message.guid!);
    }
  }

  /// Clear animation flag for a message
  void clearAnimating(Message message, {bool mounted = true}) {
    if (mounted && message.guid != null) {
      animatingMessageGuids.remove(message.guid!);
    }
  }

  /// iOS/Samsung: the row grows hidden under the flying send bubble and fades in just before it lands.
  Widget buildSentMessageAnimation({
    required Widget child,
    required Animation<double> animation,
  }) {
    return _buildSizeTransition(
      animation: animation,
      child: FadeTransition(
        opacity: animation.drive(
          Tween<double>(begin: 0.01, end: 1.0).chain(CurveTween(curve: MessageListAnimationConfig.sentFadeInterval)),
        ),
        child: child,
      ),
    );
  }

  /// Material skin: no flying send bubble, the row grows in place from its bottom-right corner.
  Widget buildMaterialSentMessageAnimation({
    required Widget child,
    required Animation<double> animation,
  }) {
    final curved = animation.drive(CurveTween(curve: MessageListAnimationConfig.entrance.curve));
    return SizeTransition(
      sizeFactor: curved,
      alignment: Alignment.bottomRight,
      child: FadeTransition(
        opacity: animation.drive(
          Tween<double>(begin: 0.01, end: 1.0)
              .chain(CurveTween(curve: MessageListAnimationConfig.materialSentFadeInterval)),
        ),
        child: ScaleTransition(
          scale: curved.drive(Tween<double>(begin: MessageListAnimationConfig.materialSentScaleStart, end: 1.0)),
          alignment: Alignment.bottomRight,
          child: child,
        ),
      ),
    );
  }

  Widget buildReceivedMessageAnimation({
    required Widget child,
    required Animation<double> animation,
  }) {
    return Builder(
      builder: (context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.01, end: 1),
        duration: M3EMotion.effectsFast.duration,
        curve: M3EMotion.strongEaseOut,
        builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
        child: MediaQuery.disableAnimationsOf(context)
            ? child
            : _buildSizeTransition(child: child, animation: animation),
      ),
    );
  }

  Widget _buildSizeTransition({
    required Widget child,
    required Animation<double> animation,
  }) {
    return SizeTransition(
      sizeFactor: animation.drive(
        Tween<double>(
          begin: MessageListAnimationConfig.sizeTransitionStartRatio,
          end: 1.0,
        ).chain(
          CurveTween(curve: MessageListAnimationConfig.entrance.curve),
        ),
      ),
      alignment: const AlignmentDirectional(-1.0, MessageListAnimationConfig.sizeTransitionAxisAlignment),
      child: child,
    );
  }
}
