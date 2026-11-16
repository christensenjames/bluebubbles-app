import 'package:bluebubbles/app/components/m3e/m3e_motion.dart';
import 'package:flutter/material.dart';

/// Centralizes all animation configuration for the message list.
/// This makes animation timing and curves easy to tune without touching the orchestrator logic.
class MessageListAnimationConfig {
  static const M3EMotionSpec entrance = M3EMotion.spatialFast;

  // The iOS/Samsung send flight (300ms) is removed the moment it lands, so the hidden row underneath must be
  // opaque by then, with margin for the DB write that precedes its insertion.
  static const Interval sentFadeInterval = Interval(0.8, 1.0, curve: Easing.standard);

  /// Material sent rows fade in over the first 150ms (`M3EMotion.effectsFast`) of the 200ms grow.
  static const Interval materialSentFadeInterval = Interval(0.0, 0.75, curve: Easing.standard);

  static const double materialSentScaleStart = 0.95;

  /// Size transition start ratio (messages start at 30% height)
  static const double sizeTransitionStartRatio = 0.3;

  /// Size transition axis alignment (-1.0 = top aligned, 1.0 = bottom aligned)
  static const double sizeTransitionAxisAlignment = -1.0;
}
