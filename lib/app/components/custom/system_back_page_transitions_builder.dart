import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PredictiveBackEvent, SwipeEdge;

/// Android page transition whose back motion copies what the system draws between two activities, as in the Settings
/// app (AOSP `DefaultCrossActivityBackAnimation`, `activity_close_exit.xml`, `activity_close_enter.xml`).
///
/// During a back swipe the page shrinks into a card over the dimmed, shrunken previous page; on release the card fades
/// out while the previous page grows back. A pop without a gesture (header back arrow, 3-button back) moves the page
/// 96dp right as it fades, over the previous page sliding in from 96dp left. Pushes keep Flutter's fade-forwards.
class SystemBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const SystemBackPageTransitionsBuilder();

  static const FadeForwardsPageTransitionsBuilder _fadeForwards = FadeForwardsPageTransitionsBuilder();

  @override
  Duration get transitionDuration => _fadeForwards.transitionDuration;

  @override
  Duration get reverseTransitionDuration => _closeDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _BackGestureObserver(
      route: route,
      child: ValueListenableBuilder<_BackGesture?>(
        valueListenable: _backGesture,
        builder: (context, gesture, _) {
          final NavigatorState? navigator = route.navigator;
          if (gesture != null && gesture.navigator == navigator && navigator!.userGestureInProgress) {
            return gesture.route == route
                ? _ClosingCard(gesture: gesture, animation: animation, child: child)
                : _EnteringPage(gesture: gesture, secondaryAnimation: secondaryAnimation, child: child);
          }
          return _CloseTransition(
            animation: animation,
            secondaryAnimation: secondaryAnimation,
            builder: (animation, secondaryAnimation) =>
                _fadeForwards.buildTransitions(route, context, animation, secondaryAnimation, child),
          );
        },
      ),
    );
  }
}

const Duration _closeDuration = Duration(milliseconds: 450);
const double _exitFadeDelayMs = 35;
const double _exitFadeMs = 83;
const double _minScale = 0.9;
const double _margin = 8;
const double _enteringOffset = 96;
const double _scrimAlphaDark = 0.8;
const double _scrimAlphaLight = 0.2;
const Curve _gestureCurve = Cubic(0.1, 0.1, 0, 1);
const Curve _emphasized = Curves.easeInOutCubicEmphasized;

class _BackGesture {
  const _BackGesture({
    required this.route,
    required this.navigator,
    required this.fromRight,
    required this.dy,
    this.commitProgress,
  });

  final PageRoute<dynamic> route;
  final NavigatorState navigator;
  final bool fromRight;
  final double dy;
  final double? commitProgress;
}

final ValueNotifier<_BackGesture?> _backGesture = ValueNotifier<_BackGesture?>(null);

double _yShift(Size size, double scale, double dy) {
  final double half = size.height / 2;
  final double ratio = Curves.decelerate.transform(math.min(half, dy.abs()) / half);
  return math.max(0.0, (size.height - size.height * scale) / 2 - _margin) * ratio * dy.sign;
}

Rect _closingRect(Size size, double progress, _BackGesture gesture) {
  final double scale = lerpDouble(1, _minScale, progress)!;
  final double targetLeft =
      gesture.fromRight ? size.width * (1 - _minScale) / 2 : size.width * (1 - _minScale) - _margin;
  final double top = progress * size.height * (1 - _minScale) / 2 + _yShift(size, scale, gesture.dy);
  return Rect.fromLTWH(progress * targetLeft, top, size.width * scale, size.height * scale);
}

Rect _enteringRect(Size size, double progress, _BackGesture gesture) {
  final double scale = lerpDouble(1, _minScale, progress)!;
  final double top = progress * size.height * (1 - _minScale) / 2 + _yShift(size, scale, gesture.dy);
  return Rect.fromLTWH(
      -_enteringOffset + progress * size.width * (1 - _minScale) / 2, top, size.width * scale, size.height * scale);
}

Widget _card(BuildContext context, Rect rect, Size size, Widget child) {
  final double scale = rect.width / size.width;
  return Transform(
    transform: Matrix4.diagonal3Values(scale, scale, 1)..setTranslationRaw(rect.left, rect.top, 0),
    child: ClipRRect(
      borderRadius: MediaQuery.displayCornerRadiiOf(context) ?? BorderRadius.zero,
      child: child,
    ),
  );
}

class _BackGestureObserver extends StatefulWidget {
  const _BackGestureObserver({required this.route, required this.child});

  final PageRoute<dynamic> route;
  final Widget child;

  @override
  State<_BackGestureObserver> createState() => _BackGestureObserverState();
}

class _BackGestureObserverState extends State<_BackGestureObserver> with WidgetsBindingObserver {
  double? _startY;

  void _track(PredictiveBackEvent event) {
    final double? y = event.touchOffset?.dy;
    _startY ??= y;
    _backGesture.value = _BackGesture(
      route: widget.route,
      navigator: widget.route.navigator!,
      fromRight: event.swipeEdge == SwipeEdge.right,
      dy: y == null ? 0 : y - _startY!,
    );
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (backEvent.isButtonEvent || !widget.route.isCurrent || !widget.route.popGestureEnabled) return false;
    _startY = null;
    _track(backEvent);
    widget.route.handleStartBackGesture(progress: 1 - backEvent.progress);
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    _track(backEvent);
    widget.route.handleUpdateBackGestureProgress(progress: 1 - backEvent.progress);
  }

  @override
  void handleCancelBackGesture() => widget.route.handleCancelBackGesture();

  @override
  void handleCommitBackGesture() {
    final _BackGesture? gesture = _backGesture.value;
    if (gesture != null && gesture.route == widget.route) {
      // Read before committing: the commit restarts the route's animation from 1.0.
      _backGesture.value = _BackGesture(
        route: gesture.route,
        navigator: gesture.navigator,
        fromRight: gesture.fromRight,
        dy: gesture.dy,
        commitProgress: _gestureCurve.transform(1 - widget.route.animation!.value),
      );
    }
    widget.route.handleCommitBackGesture();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ClosingCard extends StatelessWidget {
  const _ClosingCard({required this.gesture, required this.animation, required this.child});

  final _BackGesture gesture;
  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final Size size = constraints.biggest;
      final double? commitProgress = gesture.commitProgress;
      if (commitProgress == null) {
        return _card(context, _closingRect(size, _gestureCurve.transform(1 - animation.value), gesture), size, child);
      }
      final double t = 1 - animation.value;
      final Rect start = _closingRect(size, commitProgress, gesture);
      final Rect end = Rect.fromLTWH(start.left + _enteringOffset, 0, size.width, size.height);
      return Opacity(
        opacity: math.max(1 - t * 5, 0),
        child: _card(context, Rect.lerp(start, end, _emphasized.transform(t))!, size, child),
      );
    });
  }
}

class _EnteringPage extends StatelessWidget {
  const _EnteringPage({required this.gesture, required this.secondaryAnimation, required this.child});

  final _BackGesture gesture;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double maxScrim = theme.brightness == Brightness.dark ? _scrimAlphaDark : _scrimAlphaLight;
    return LayoutBuilder(builder: (context, constraints) {
      final Size size = constraints.biggest;
      final double t = 1 - secondaryAnimation.value;
      final double? commitProgress = gesture.commitProgress;
      final Rect rect = commitProgress == null
          ? _enteringRect(size, _gestureCurve.transform(t), gesture)
          : Rect.lerp(_enteringRect(size, commitProgress, gesture), Offset.zero & size, _emphasized.transform(t))!;
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: theme.colorScheme.surface),
          _card(context, rect, size, child),
          ColoredBox(color: Colors.black.withValues(alpha: commitProgress == null ? maxScrim : maxScrim * (1 - t))),
        ],
      );
    });
  }
}

class _CloseTransition extends StatefulWidget {
  const _CloseTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.builder,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget Function(Animation<double> animation, Animation<double> secondaryAnimation) builder;

  @override
  State<_CloseTransition> createState() => _CloseTransitionState();
}

class _CloseTransitionState extends State<_CloseTransition> {
  // Only a pop of a fully settled page uses the close motion; a pop that interrupts a push keeps FadeForwards' reverse
  // so it doesn't jump. Status listeners fire inside reverse(), before the first tick has moved the value off 1.0.
  bool _exiting = false;
  bool _revealing = false;

  void _onPrimaryStatus(AnimationStatus status) => setState(() {
        _exiting = status == AnimationStatus.reverse && widget.animation.value == 1.0;
      });

  void _onSecondaryStatus(AnimationStatus status) => setState(() {
        _revealing = status == AnimationStatus.reverse && widget.secondaryAnimation.value == 1.0;
      });

  @override
  void initState() {
    super.initState();
    widget.animation.addStatusListener(_onPrimaryStatus);
    widget.secondaryAnimation.addStatusListener(_onSecondaryStatus);
  }

  @override
  void didUpdateWidget(_CloseTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      oldWidget.animation.removeStatusListener(_onPrimaryStatus);
      widget.animation.addStatusListener(_onPrimaryStatus);
    }
    if (oldWidget.secondaryAnimation != widget.secondaryAnimation) {
      oldWidget.secondaryAnimation.removeStatusListener(_onSecondaryStatus);
      widget.secondaryAnimation.addStatusListener(_onSecondaryStatus);
    }
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onPrimaryStatus);
    widget.secondaryAnimation.removeStatusListener(_onSecondaryStatus);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget page = widget.builder(
      _exiting ? kAlwaysCompleteAnimation : widget.animation,
      _revealing ? kAlwaysDismissedAnimation : widget.secondaryAnimation,
    );
    if (_exiting) {
      final double t = 1 - widget.animation.value;
      final double elapsedMs = t * _closeDuration.inMilliseconds;
      return Opacity(
        opacity: 1 - ((elapsedMs - _exitFadeDelayMs) / _exitFadeMs).clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(_enteringOffset * _emphasized.transform(t), 0), child: page),
      );
    }
    if (_revealing) {
      final double t = 1 - widget.secondaryAnimation.value;
      return ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Transform.translate(offset: Offset(-_enteringOffset * (1 - _emphasized.transform(t)), 0), child: page),
      );
    }
    return page;
  }
}
