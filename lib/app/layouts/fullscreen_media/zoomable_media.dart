import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef _View = ({double scale, Offset offset});

const _View _identity = (scale: 1.0, offset: Offset.zero);
const double _minScale = 1.0;
const double _zoomEpsilon = 1e-3;
const double _rubberCoefficient = 0.55;
const double _scaleRubberRange = 0.35;
const double _rubberRearm = 1.03;
const double _dismissDistanceFactor = 0.35;
const double _dismissShrink = 0.15;
const double _dismissFlickVelocity = 700;
const double _dismissCommitProgress = 0.5;
const double _flingDrag = 0.135;
const double _panZoomScaleSlop = 0.05;

final SpringDescription _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 600);

/// Renders [child] fit-contained in the viewport with pinch, pan and double-tap zoom.
///
/// At scale 1 a one-finger drag is left to ancestors (a PageView pages, a [SwipeToDismiss] closes); a second
/// finger always wins the gesture arena immediately so pinch works on the first touch.
class ZoomableMedia extends StatefulWidget {
  const ZoomableMedia({
    super.key,
    required this.child,
    required this.childSize,
    this.maxScale = 10.0,
    this.doubleTapScale = 2.5,
    this.onTap,
    this.onZoomChanged,
  });

  final Widget child;
  final Size childSize;
  final double maxScale;
  final double doubleTapScale;
  final VoidCallback? onTap;
  final ValueChanged<bool>? onZoomChanged;

  @override
  State<ZoomableMedia> createState() => _ZoomableMediaState();
}

class _ZoomableMediaState extends State<ZoomableMedia> with SingleTickerProviderStateMixin {
  final ValueNotifier<_View> _view = ValueNotifier<_View>(_identity);
  late final AnimationController _controller;
  ValueChanged<double>? _step;

  Size _viewport = Size.zero;
  Size _fitted = Size.zero;
  bool _disableAnimations = false;
  bool _zoomed = false;
  bool _suppressTap = false;
  Offset _doubleTapPosition = Offset.zero;

  Offset _lastFocal = Offset.zero;
  double _rawScale0 = 1.0;
  Offset _anchor = Offset.zero;
  bool _inZone = false;

  late final Map<Type, GestureRecognizerFactory> _gestures = <Type, GestureRecognizerFactory>{
    TapGestureRecognizer: GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
      () => TapGestureRecognizer(debugOwner: this),
      (TapGestureRecognizer r) => r.onTap = _handleTap,
    ),
    DoubleTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
      () => DoubleTapGestureRecognizer(debugOwner: this),
      (DoubleTapGestureRecognizer r) => r
        ..onDoubleTapDown = ((TapDownDetails d) => _doubleTapPosition = d.localPosition)
        ..onDoubleTap = _handleDoubleTap,
    ),
    _ZoomGestureRecognizer: GestureRecognizerFactoryWithHandlers<_ZoomGestureRecognizer>(
      () => _ZoomGestureRecognizer(debugOwner: this),
      (_ZoomGestureRecognizer r) => r
        ..shouldClaimSingle = _shouldClaimSingle
        ..onDown = _onDown
        ..onStart = _onStart
        ..onUpdate = _onUpdate
        ..onEnd = _onEnd,
    ),
  };

  Offset get _center => Offset(_viewport.width / 2, _viewport.height / 2);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this)..addListener(() => _step?.call(_controller.value));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _disableAnimations = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void dispose() {
    _controller.dispose();
    _view.dispose();
    super.dispose();
  }

  void _syncGeometry(Size viewport) {
    final Size fitted = widget.childSize.isEmpty
        ? viewport
        : applyBoxFit(BoxFit.contain, widget.childSize, viewport).destination;
    if (viewport == _viewport && fitted == _fitted) return;
    _viewport = viewport;
    _fitted = fitted;
    if (_view.value.scale > 1) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final double scale = _view.value.scale.clamp(_minScale, widget.maxScale);
        _setView((scale: scale, offset: _clampOffset(_view.value.offset, scale)));
      });
    }
  }

  Offset _bounds(double scale) => Offset(
    math.max(0, (_fitted.width * scale - _viewport.width) / 2),
    math.max(0, (_fitted.height * scale - _viewport.height) / 2),
  );

  Offset _clampOffset(Offset offset, double scale) {
    final Offset b = _bounds(scale);
    return Offset(offset.dx.clamp(-b.dx, b.dx), offset.dy.clamp(-b.dy, b.dy));
  }

  void _setView(_View view) {
    _view.value = view;
    final bool zoomed = view.scale > 1 + _zoomEpsilon;
    if (zoomed != _zoomed) {
      _zoomed = zoomed;
      widget.onZoomChanged?.call(zoomed);
    }
  }

  void _run(Simulation simulation, ValueChanged<double> step, {VoidCallback? onDone}) {
    _step = step;
    _controller.animateWith(simulation).then((_) => onDone?.call());
  }

  void _animateTo(_View target) {
    final _View from = _view.value;
    if (_disableAnimations || from == target) {
      _setView(target);
      return;
    }
    _run(
      SpringSimulation(_spring, 0, 1, 0),
      (double t) => _setView((
        scale: from.scale + (target.scale - from.scale) * t,
        offset: from.offset + (target.offset - from.offset) * t,
      )),
      onDone: () => _setView(target),
    );
  }

  Offset _reanchor(_View view, double scale, Offset position) {
    final Offset focal = position - _center;
    return focal - (focal - view.offset) * (scale / view.scale);
  }

  void _handleTap() {
    if (_suppressTap) {
      _suppressTap = false;
      return;
    }
    widget.onTap?.call();
  }

  void _handleDoubleTap() {
    if (_zoomed) {
      _animateTo(_identity);
      return;
    }
    final _View view = _view.value;
    final double target = math.min(widget.doubleTapScale, widget.maxScale);
    _animateTo((scale: target, offset: _clampOffset(_reanchor(view, target, _doubleTapPosition), target)));
  }

  bool _shouldClaimSingle(Offset delta) {
    final _View view = _view.value;
    if (!_zoomed) return false;
    if (delta.dx.abs() <= delta.dy.abs()) return true;
    final double bound = _bounds(view.scale).dx;
    return delta.dx > 0 ? view.offset.dx < bound - 0.5 : view.offset.dx > 0.5 - bound;
  }

  void _onDown() {
    _suppressTap = _controller.isAnimating;
    _controller.stop();
  }

  void _onStart(Offset focal) {
    final _View view = _view.value;
    _lastFocal = focal;
    _rawScale0 = _unrubberScale(view.scale);
    _anchor = (focal - _center - _unrubberOffset(view.offset, view.scale)) / view.scale;
    _inZone = _rawScale0 > widget.maxScale || _rawScale0 < _minScale;
  }

  void _onUpdate(Offset focal, double ratio) {
    _lastFocal = focal;
    final double rawScale = _rawScale0 * ratio;
    final bool outside = rawScale > widget.maxScale || rawScale < _minScale;
    if (outside && !_inZone) {
      _inZone = true;
      HapticFeedback.selectionClick();
    } else if (rawScale <= widget.maxScale / _rubberRearm && rawScale >= _minScale * _rubberRearm) {
      _inZone = false;
    }
    final double scale = _rubberScale(rawScale);
    final Offset b = _bounds(scale);
    Offset raw = focal - _center - _anchor * scale;
    // An axis that fits the viewport stays centred, as in Google Photos; re-anchoring keeps the hand-off continuous.
    if (b.dx == 0) {
      _anchor = Offset((focal.dx - _center.dx) / scale, _anchor.dy);
      raw = Offset(0, raw.dy);
    }
    if (b.dy == 0) {
      _anchor = Offset(_anchor.dx, (focal.dy - _center.dy) / scale);
      raw = Offset(raw.dx, 0);
    }
    _setView((scale: scale, offset: _rubberOffset(raw, scale)));
  }

  void _onEnd(Velocity velocity) {
    final _View view = _view.value;
    final double scale = view.scale.clamp(_minScale, widget.maxScale);
    final Offset offset = _clampOffset(_reanchor(view, scale, _lastFocal), scale);
    if (scale != view.scale || offset != view.offset) {
      _animateTo((scale: scale, offset: offset));
      return;
    }
    final Offset flick = velocity.pixelsPerSecond;
    if (!_zoomed || flick.distance <= kMinFlingVelocity) return;
    final Offset direction = flick / flick.distance;
    final double speed = math.min(flick.distance, kMaxFlingVelocity);
    _run(
      FrictionSimulation(_flingDrag, 0, speed),
      (double travelled) => _setView((scale: scale, offset: _clampOffset(offset + direction * travelled, scale))),
    );
  }

  double _rubber(double distance, double range) => (1 - 1 / (distance * _rubberCoefficient / range + 1)) * range;

  double _rubberInverse(double resisted, double range) {
    final double y = math.min(resisted, range * 0.999);
    return range / _rubberCoefficient * (y / (range - y));
  }

  double _rubberScale(double raw) {
    final double max = widget.maxScale;
    if (raw > max) return max * math.exp(_rubber(math.log(raw / max), _scaleRubberRange));
    if (raw < _minScale) return _minScale / math.exp(_rubber(math.log(_minScale / raw), _scaleRubberRange));
    return raw;
  }

  double _unrubberScale(double scale) {
    final double max = widget.maxScale;
    if (scale > max) return max * math.exp(_rubberInverse(math.log(scale / max), _scaleRubberRange));
    if (scale < _minScale) {
      return _minScale / math.exp(_rubberInverse(math.log(_minScale / scale), _scaleRubberRange));
    }
    return scale;
  }

  double _rubberAxis(double value, double bound, double range, double Function(double, double) curve) {
    final double over = value.abs() - bound;
    return over <= 0 ? value : value.sign * (bound + curve(over, range));
  }

  Offset _rubberOffset(Offset raw, double scale) {
    final Offset b = _bounds(scale);
    return Offset(
      _rubberAxis(raw.dx, b.dx, _viewport.width, _rubber),
      _rubberAxis(raw.dy, b.dy, _viewport.height, _rubber),
    );
  }

  Offset _unrubberOffset(Offset offset, double scale) {
    final Offset b = _bounds(scale);
    return Offset(
      _rubberAxis(offset.dx, b.dx, _viewport.width, _rubberInverse),
      _rubberAxis(offset.dy, b.dy, _viewport.height, _rubberInverse),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        _syncGeometry(constraints.biggest);
        return ClipRect(
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: _gestures,
            child: ValueListenableBuilder<_View>(
              valueListenable: _view,
              child: Center(
                child: SizedBox.fromSize(size: _fitted, child: widget.child),
              ),
              builder: (BuildContext context, _View view, Widget? child) => Transform(
                alignment: Alignment.center,
                transform: Matrix4.translationValues(view.offset.dx, view.offset.dy, 0)
                  ..scaleByDouble(view.scale, view.scale, 1, 1),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Drags [child] down to close: it follows the pointer and shrinks, and the release either calls [onDismiss] or
/// springs back with the release velocity.
///
/// Reads raw pointers, so a recognizer inside [child] (a video player's own drag handlers) cannot take the drag.
/// Callers lock their own PageView while [onDismissProgress] is above 0.
class SwipeToDismiss extends StatefulWidget {
  const SwipeToDismiss({
    super.key,
    required this.child,
    this.ignoredBottomFraction = 0,
    this.onDismissProgress,
    this.onDismiss,
  });

  final Widget child;

  /// Drags that start in this bottom fraction of the height are left to the child, such as a video seek bar.
  final double ignoredBottomFraction;
  final ValueChanged<double>? onDismissProgress;

  /// Null disables the gesture.
  final VoidCallback? onDismiss;

  @override
  State<SwipeToDismiss> createState() => _SwipeToDismissState();
}

class _SwipeToDismissState extends State<SwipeToDismiss> with SingleTickerProviderStateMixin {
  final ValueNotifier<Offset> _offset = ValueNotifier<Offset>(Offset.zero);
  late final AnimationController _controller;
  final Set<int> _pointers = <int>{};
  int? _pointer;
  Offset? _slopStart;
  Offset? _pan0;
  bool _dragging = false;
  Offset _grab = Offset.zero;
  Offset _springFrom = Offset.zero;
  VelocityTracker? _tracker;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(vsync: this)
      ..addListener(() => _set(_springFrom * (1 - _controller.value)));
  }

  @override
  void dispose() {
    _controller.dispose();
    _offset.dispose();
    super.dispose();
  }

  double get _height => context.size?.height ?? 0;

  double _progressOf(Offset offset) =>
      _height == 0 ? 0 : (offset.dy / (_height * _dismissDistanceFactor)).clamp(0.0, 1.0);

  // Progress is stored before the offset notifies, so the transform's builder never measures during build.
  void _set(Offset offset) {
    final double progress = _progressOf(offset);
    final bool changed = progress != _progress;
    _progress = progress;
    _offset.value = offset;
    if (changed) widget.onDismissProgress?.call(progress);
  }

  void _start(int pointer, PointerDeviceKind kind, Offset position, Duration timeStamp) {
    _pointers.add(pointer);
    if (_pointers.length > 1) {
      // A second finger is a pinch, which the child owns.
      if (_pointer != null) _abandon();
      return;
    }
    if (widget.onDismiss == null) return;
    if (position.dy > _height * (1 - widget.ignoredBottomFraction)) return;
    _controller.stop();
    _pointer = pointer;
    _slopStart = position;
    _tracker = VelocityTracker.withKind(kind)..addPosition(timeStamp, position);
  }

  void _move(int pointer, Offset position, Duration timeStamp) {
    if (pointer != _pointer) return;
    _tracker!.addPosition(timeStamp, position);
    final Offset? slopStart = _slopStart;
    if (slopStart != null) {
      final Offset moved = position - slopStart;
      if (moved.distance < kTouchSlop) return;
      _slopStart = null;
      if (moved.dy <= moved.dx.abs()) {
        _abandon();
        return;
      }
      _dragging = true;
      _grab = position - _offset.value;
    }
    _set(position - _grab);
  }

  void _end(int pointer) {
    _pointers.remove(pointer);
    if (pointer != _pointer) return;
    final Velocity velocity = _tracker!.getVelocity();
    final bool dragging = _dragging;
    _reset();
    final double dy = velocity.pixelsPerSecond.dy;
    if (dragging && ((_progress >= _dismissCommitProgress && dy >= 0) || dy > _dismissFlickVelocity)) {
      widget.onDismiss!();
      return;
    }
    _springBack(velocity);
  }

  void _cancel(int pointer) {
    _pointers.remove(pointer);
    if (pointer == _pointer) _abandon();
  }

  void _abandon() {
    _reset();
    _springBack(Velocity.zero);
  }

  void _reset() {
    _pointer = null;
    _slopStart = null;
    _pan0 = null;
    _dragging = false;
    _tracker = null;
  }

  void _springBack(Velocity velocity) {
    final Offset from = _offset.value;
    if (from.distance < 1 || MediaQuery.disableAnimationsOf(context)) {
      _set(Offset.zero);
      return;
    }
    _springFrom = from;
    // The spring runs t from 0 to 1 along from → zero, so the release velocity is projected onto that path.
    final Offset v = velocity.pixelsPerSecond;
    final double t0 = -(v.dx * from.dx + v.dy * from.dy) / from.distanceSquared;
    _controller.value = 0;
    _controller.animateWith(SpringSimulation(_spring, 0, 1, t0)).then((_) => _set(Offset.zero));
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) => _start(e.pointer, e.kind, e.localPosition, e.timeStamp),
      onPointerMove: (e) => _move(e.pointer, e.localPosition, e.timeStamp),
      onPointerUp: (e) => _end(e.pointer),
      onPointerCancel: (e) => _cancel(e.pointer),
      onPointerPanZoomStart: (e) => _start(e.pointer, e.kind, e.localPosition, e.timeStamp),
      onPointerPanZoomUpdate: (e) {
        if (e.pointer != _pointer) return;
        if ((e.scale - 1).abs() >= _panZoomScaleSlop) {
          _cancel(e.pointer);
          return;
        }
        // Flutter's Linux embedder carries the previous gesture's pan into the next one, so measure from the first.
        _move(e.pointer, e.localPosition + e.localPan - (_pan0 ??= e.localPan), e.timeStamp);
      },
      onPointerPanZoomEnd: (e) => _end(e.pointer),
      child: ValueListenableBuilder<Offset>(
        valueListenable: _offset,
        child: widget.child,
        builder: (BuildContext context, Offset offset, Widget? child) {
          final double scale = 1 - _dismissShrink * _progress;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.translationValues(offset.dx, offset.dy, 0)..scaleByDouble(scale, scale, 1, 1),
            child: child,
          );
        },
      ),
    );
  }
}

class _ZoomGestureRecognizer extends OneSequenceGestureRecognizer {
  _ZoomGestureRecognizer({super.debugOwner});

  late bool Function(Offset delta) shouldClaimSingle;
  late VoidCallback onDown;
  late ValueChanged<Offset> onStart;
  late void Function(Offset focal, double scale) onUpdate;
  late ValueChanged<Velocity> onEnd;

  final Map<int, Offset> _positions = <int, Offset>{};
  PointerDeviceKind _kind = PointerDeviceKind.touch;
  Offset _downPosition = Offset.zero;
  bool _claimed = false;
  double _baseSpan = 0;
  int? _panZoomPointer;
  double _panZoomScale = 1;
  Offset? _panZoomPan0;
  double _panZoomBase = 1;
  VelocityTracker? _tracker;
  Velocity _endVelocity = Velocity.zero;
  bool _disposed = false;

  Offset get _focal =>
      _positions.values.fold(Offset.zero, (Offset a, Offset b) => a + b) / _positions.length.toDouble();

  double get _span {
    final Offset focal = _focal;
    return _positions.values.fold(0.0, (double a, Offset p) => a + (p - focal).distance) / _positions.length;
  }

  double get _ratio {
    if (_panZoomPointer != null) return _panZoomScale / _panZoomBase;
    return _positions.length > 1 && _baseSpan > 0 ? _span / _baseSpan : 1.0;
  }

  @override
  String get debugDescription => 'zoom';

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _kind = event.kind;
    _positions[event.pointer] = event.localPosition;
    onDown();
    if (_positions.length == 1) _downPosition = event.localPosition;
    if (_claimed) {
      resolvePointer(event.pointer, GestureDisposition.accepted);
      _rebase();
    } else if (_positions.length > 1) {
      _claim();
    }
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    super.addAllowedPointerPanZoom(event);
    startTrackingPointer(event.pointer, event.transform);
    _kind = event.kind;
    _panZoomPointer = event.pointer;
    _panZoomScale = 1;
    _panZoomPan0 = null;
    _positions[event.pointer] = event.localPosition;
    onDown();
  }

  void _claim() {
    _claimed = true;
    resolve(GestureDisposition.accepted);
    _rebase();
  }

  void _rebase() {
    _baseSpan = _span;
    _panZoomBase = _panZoomScale;
    _tracker = VelocityTracker.withKind(_kind);
    onStart(_focal);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent || event is PointerPanZoomUpdateEvent) {
      if (!_positions.containsKey(event.pointer)) return;
      final Offset delta;
      var pinched = false;
      if (event is PointerPanZoomUpdateEvent) {
        // Flutter's Linux embedder carries the previous gesture's pan into the next one, so measure from the first.
        final Offset pan = event.localPan - (_panZoomPan0 ??= event.localPan);
        _positions[event.pointer] = event.localPosition + pan;
        _panZoomScale = event.scale;
        delta = pan;
        pinched = (event.scale - 1).abs() >= _panZoomScaleSlop;
      } else {
        _positions[event.pointer] = event.localPosition;
        delta = event.localPosition - _downPosition;
      }
      if (_claimed) {
        _tracker?.addPosition(event.timeStamp, _focal);
        onUpdate(_focal, _ratio);
      } else if (pinched) {
        _claim();
      } else if (delta.distance >= computeHitSlop(event.kind, null) && shouldClaimSingle(delta)) {
        _claim();
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent || event is PointerPanZoomEndEvent) {
      _positions.remove(event.pointer);
      if (_positions.isNotEmpty) {
        if (_claimed) _rebase();
      } else if (!_claimed) {
        resolve(GestureDisposition.rejected);
      } else if (event is! PointerCancelEvent) {
        _endVelocity = _tracker?.getVelocity() ?? Velocity.zero;
      }
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    _positions.remove(pointer);
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    final Velocity velocity = _endVelocity;
    _endVelocity = Velocity.zero;
    _claimed = false;
    _panZoomPointer = null;
    _positions.clear();
    _tracker = null;
    if (!_disposed) onEnd(velocity);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
