import 'package:flutter/material.dart';

/// Centralizes all animation configuration for the message list.
/// This makes animation timing and curves easy to tune without touching the orchestrator logic.
class MessageListAnimationConfig {
  static const Curve entranceCurve = Easing.emphasizedDecelerate;

  /// Slightly longer duration delays the outgoing fade-in handoff so the
  /// temporary send bubble and list row don't visually overlap as tightly.
  static const Duration sentInsertionDuration = Duration(milliseconds: 475);

  /// Receiving is a high-frequency event with no send-bubble handoff, so it stays inside the 300ms UI budget.
  static const Duration receivedInsertionDuration = Durations.short4;

  /// Curve for insertion slide animation
  static const Curve insertionSlideCurve = entranceCurve;

  /// Curve for insertion size animation
  static const Curve insertionSizeCurve = entranceCurve;

  /// Curve for insertion fade animation (only for sent messages)
  static const Curve insertionFadeCurve = Easing.standard;

  /// Fade interval for sent messages (0.9-1.0 of animation)
  static const Interval fadeInterval = Interval(0.9, 1.0, curve: Easing.standard);

  /// Size transition start ratio (messages start at 30% height)
  static const double sizeTransitionStartRatio = 0.3;

  /// Slide transition start offset (messages slide up from bottom)
  static const Offset slideStartOffset = Offset(0.0, 1.0);

  /// Size transition axis alignment (-1.0 = top aligned, 1.0 = bottom aligned)
  static const double sizeTransitionAxisAlignment = -1.0;
}
