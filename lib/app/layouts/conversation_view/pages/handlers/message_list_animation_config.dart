import 'package:flutter/material.dart';

/// Centralizes all animation configuration for the message list.
/// This makes animation timing and curves easy to tune without touching the orchestrator logic.
class MessageListAnimationConfig {
  /// Strong ease-out for entering UI. Flutter's Curves.easeOut is
  /// Cubic(0.0, 0.0, 0.58, 1.0), which is too weak to read as deliberate.
  static const Curve strongEaseOut = Cubic(0.23, 1.0, 0.32, 1.0);

  /// Duration for outgoing message insertion (slide + size + fade).
  ///
  /// Slightly longer duration delays the outgoing fade-in handoff so the
  /// temporary send bubble and list row don't visually overlap as tightly.
  static const Duration sentInsertionDuration = Duration(milliseconds: 475);

  /// Duration for incoming message insertion. Receiving is a high-frequency
  /// event with no send-bubble handoff, so it stays inside the 300ms UI budget.
  static const Duration receivedInsertionDuration = Duration(milliseconds: 200);

  /// Curve for insertion slide animation
  static const Curve insertionSlideCurve = strongEaseOut;

  /// Curve for insertion size animation
  static const Curve insertionSizeCurve = strongEaseOut;

  /// Curve for insertion fade animation (only for sent messages)
  static const Curve insertionFadeCurve = strongEaseOut;

  /// Fade interval for sent messages (0.9-1.0 of animation)
  static const Interval fadeInterval = Interval(0.9, 1.0, curve: Curves.easeOut);

  /// Size transition start ratio (messages start at 30% height)
  static const double sizeTransitionStartRatio = 0.3;

  /// Slide transition start offset (messages slide up from bottom)
  static const Offset slideStartOffset = Offset(0.0, 1.0);

  /// Size transition axis alignment (-1.0 = top aligned, 1.0 = bottom aligned)
  static const double sizeTransitionAxisAlignment = -1.0;
}
