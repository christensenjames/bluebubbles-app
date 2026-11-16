import 'package:bluebubbles/app/components/m3e/m3e_motion.dart';
import 'package:bluebubbles/app/state/message_state_scope.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reaction/reaction.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:defer_pointer/defer_pointer.dart';
import 'package:flutter/material.dart';

/// Stateful widget that animates a reaction pop-in only once
class _ReactionAnimator extends StatefulWidget {
  const _ReactionAnimator({
    super.key,
    required this.stableKey,
    required this.shouldAnimate,
    required this.alignment,
    required this.child,
  });

  final String stableKey;
  final bool shouldAnimate;

  /// The reaction's corner that overlaps the bubble; the pop-in grows out of it.
  final Alignment alignment;
  final Widget child;

  @override
  State<_ReactionAnimator> createState() => _ReactionAnimatorState();
}

class _ReactionAnimatorState extends State<_ReactionAnimator> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: M3EMotion.spatialFast.duration,
      vsync: this,
    );

    _scaleAnimation = _controller.drive(
      Tween<double>(begin: 0.9, end: 1.0).chain(CurveTween(curve: M3EMotion.spatialFast.curve)),
    );
    // Opacity finishes in effectsFast's 150ms of the 200ms scale.
    _fadeAnimation = _controller.drive(
      Tween<double>(begin: 0.01, end: 1.0).chain(CurveTween(curve: const Interval(0.0, 0.75, curve: Easing.standard))),
    );

    // Animate in only if this is a new reaction
    if (widget.shouldAnimate) {
      _controller.forward();
    } else {
      // Skip animation - set to final state immediately
      _controller.value = 1.0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.matchReducedMotion(context, M3EMotion.spatialFast.duration);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        alignment: widget.alignment,
        child: widget.child,
      ),
    );
  }
}

class ReactionHolder extends StatefulWidget {
  const ReactionHolder({
    super.key,
    required this.reactions,
  });

  final Iterable<Message> reactions;

  @override
  State<ReactionHolder> createState() => _ReactionHolderState();
}

class _ReactionHolderState extends State<ReactionHolder> {
  Iterable<Message> get reactions => getUniqueReactionMessages(widget.reactions.toList());

  // Cache the unique reactions to prevent unnecessary rebuilds
  late List<Message> _cachedReactions;

  // Track which reaction keys have been animated
  // This prevents re-animation on rebuilds, but allows animation on first appearance
  final Set<String> _seenReactionKeys = {};

  @override
  void initState() {
    super.initState();
    _cachedReactions = reactions.toList();
  }

  @override
  void didUpdateWidget(ReactionHolder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only rebuild if reactions actually changed
    if (!_reactionsEqual(oldWidget.reactions, widget.reactions)) {
      _cachedReactions = reactions.toList();
    }
  }

  /// Check if two reaction lists are equal by comparing GUIDs
  /// This prevents unnecessary rebuilds when the same data is passed
  bool _reactionsEqual(Iterable<Message> a, Iterable<Message> b) {
    final listA = a.toList();
    final listB = b.toList();
    if (listA.length != listB.length) return false;
    for (int i = 0; i < listA.length; i++) {
      if (listA[i].guid != listB[i].guid) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // If the reactions are empty, return nothing
    if (_cachedReactions.isEmpty) {
      return const SizedBox.shrink();
    }

    final isFromMe = MessageStateScope.of(context).isFromMe.value;
    return SizedBox(
      height: 35,
      width: 35,
      child: Stack(
        clipBehavior: Clip.none,
        children: _cachedReactions
            .asMap()
            .entries
            .map((entry) {
              final i = entry.key;
              final e = entry.value;
              // Stable across the temp GUID -> real GUID swap, but distinct per emoji:
              // an arbitrary-emoji tapback shares the "emoji" type with every other one.
              final sender = e.isFromMe! ? 0 : e.handleId ?? 0;
              final stableKey =
                  '${e.associatedMessageGuid}-${e.associatedMessageType}-${e.associatedMessageEmoji ?? ''}-$sender';

              // Check if this is a new reaction that should animate
              final shouldAnimate = !_seenReactionKeys.contains(stableKey);
              if (shouldAnimate) {
                // Mark as seen for future rebuilds
                _seenReactionKeys.add(stableKey);
              }

              return Positioned(
                key: ValueKey(stableKey),
                top: 0,
                left: !isFromMe ? null : -i * 2.0,
                right: isFromMe ? null : -i * 2.0,
                child: DeferPointer(
                  child: _ReactionAnimator(
                    key: ValueKey(stableKey),
                    stableKey: stableKey,
                    shouldAnimate: shouldAnimate,
                    alignment: isFromMe ? Alignment.bottomRight : Alignment.bottomLeft,
                    child: ReactionWidget(
                      reaction: e,
                      reactions: _cachedReactions,
                    ),
                  ),
                ),
              );
            })
            .toList()
            .reversed
            .toList(),
      ),
    );
  }
}
