import 'dart:async';
import 'dart:math';

import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:bluebubbles/app/wrappers/titlebar_wrapper.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class TabletModeWrapper extends StatefulWidget {
  final Widget left;
  final Widget right;
  final double initialRatio;
  final double dividerWidth;
  final double minRatio;
  final double maxRatio;
  final bool allowResize;
  final double? minWidthLeft;
  final double? maxWidthLeft;

  /// When set, the phone layout keeps [right] mounted over [left] and shows it while it has pages, so pages survive a
  /// layout switch. [left] moves as the pane's [PaneBasePage] would, so back reveals it like the page underneath.
  final PaneObserver? rightPane;

  const TabletModeWrapper(
      {super.key,
      required this.left,
      required this.right,
      this.initialRatio = 0.5,
      this.allowResize = true,
      this.dividerWidth = 7.0,
      this.minRatio = 0,
      this.maxRatio = 0,
      this.minWidthLeft,
      this.maxWidthLeft,
      this.rightPane})
      : assert(initialRatio >= 0),
        assert(initialRatio <= 1);

  @override
  State<TabletModeWrapper> createState() => _TabletModeWrapperState();
}

class _TabletModeWrapperState extends State<TabletModeWrapper> with ThemeHelpers {
  //from 0-1
  late final RxDouble _ratio;
  double? _maxWidth;
  StreamSubscription? _eventSub;

  double get _width1 => max(
      min(_ratio * _maxWidth!, widget.maxWidthLeft ?? double.infinity), widget.minWidthLeft ?? double.negativeInfinity);

  double get _width2 => _maxWidth! - _width1;

  double get _dragTargetWidth => max(widget.dividerWidth, 16);

  @override
  void initState() {
    super.initState();
    _ratio =
        RxDouble((PrefsSvc.desktop.getSplitRatio() ?? widget.initialRatio).clamp(widget.minRatio, widget.maxRatio));
    _eventSub = EventDispatcherSvc.stream.listen((event) {
      if (!mounted) return;
      if (event.type == 'split-refresh') {
        _ratio.value = PrefsSvc.desktop.getSplitRatio() ?? _ratio.value;
        setState(() {});
      } else if (event.type == 'override-split') {
        _ratio.value = event.data;
        setState(() {});
      }
    });
    debounce<double>(_ratio, (val) async {
      await PrefsSvc.desktop.setSplitRatio(val);
      EventDispatcherSvc.emit('split-refresh', null);
    });
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!showAltLayout) {
      final pane = widget.rightPane;
      if (pane == null) return TitleBarWrapper(child: widget.left);
      return TitleBarWrapper(
        child: Stack(
          children: [
            // Offstage alone keeps the hidden pane's animations running and its focusables reachable
            Obx(() {
              final base = pane.base.value;
              return Offstage(
                offstage: pane.covered.value,
                child: TickerMode(
                  enabled: !pane.covered.value,
                  child: ExcludeFocus(
                    excluding: pane.open.value,
                    // Built once the base exists, so adding its transition never reparents the left pane
                    child: base == null ? const SizedBox.shrink() : _BaseTransition(route: base, child: widget.left),
                  ),
                ),
              );
            }),
            Obx(() => IgnorePointer(ignoring: !pane.open.value, child: widget.right)),
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, BoxConstraints constraints) {
        _maxWidth = constraints.maxWidth - widget.dividerWidth;
        return TitleBarWrapper(
          child: SizedBox(
            width: constraints.maxWidth,
            child: Obx(() => Stack(
                  children: [
                    Row(
                      children: <Widget>[
                        SizedBox(
                          width: _width1,
                          child: widget.left,
                        ),
                        Container(
                          color: context.theme.colorScheme.surfaceContainerHighest,
                          width: widget.dividerWidth,
                          height: constraints.maxHeight,
                          child: widget.allowResize
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (int i = 0; i < 3; i++) ...[
                                      if (i > 0) const SizedBox(height: 20),
                                      Container(
                                          height: 4,
                                          width: 4,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(25),
                                            color: context.theme.colorScheme.onSurfaceVariant,
                                          )),
                                    ],
                                  ],
                                )
                              : null,
                        ),
                        SizedBox(
                          width: _width2,
                          child: widget.right,
                        ),
                      ],
                    ),
                    if (widget.allowResize)
                      Positioned(
                        left: _width1 + (widget.dividerWidth - _dragTargetWidth) / 2,
                        top: 0,
                        bottom: 0,
                        width: _dragTargetWidth,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.resizeLeftRight,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onPanUpdate: (DragUpdateDetails details) {
                              final box = context.findRenderObject() as RenderBox;
                              final pointerX = box.globalToLocal(details.globalPosition).dx;
                              final width = max(
                                  min(pointerX - widget.dividerWidth / 2,
                                      min(widget.maxRatio * _maxWidth!, widget.maxWidthLeft ?? double.infinity)),
                                  max(widget.minRatio * _maxWidth!, widget.minWidthLeft ?? double.negativeInfinity));
                              _ratio.value = width / _maxWidth!;
                              NavigationSvc.leftPaneNarrow.value = width < NavigatorService.avatarOnlyWidth;
                              NavigationSvc.listener.refresh();
                            },
                          ),
                        ),
                      ),
                  ],
                )),
          ),
        );
      },
    );
  }
}

class _BaseTransition extends StatelessWidget {
  const _BaseTransition({required this.route, required this.child});

  final PageRoute route;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final animation = route.animation!, secondaryAnimation = route.secondaryAnimation!;
    return ListenableBuilder(
      listenable: Listenable.merge([animation, secondaryAnimation]),
      builder: (context, child) => Theme.of(context)
          .pageTransitionsTheme
          .buildTransitions(route, context, animation, secondaryAnimation, child!),
      child: child,
    );
  }
}
