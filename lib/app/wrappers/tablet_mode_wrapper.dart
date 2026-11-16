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
  final VoidCallback? onCollapse;

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
      this.onCollapse})
      : assert(initialRatio >= 0),
        assert(initialRatio <= 1);

  @override
  State<TabletModeWrapper> createState() => _TabletModeWrapperState();
}

class _TabletModeWrapperState extends State<TabletModeWrapper> with ThemeHelpers {
  //from 0-1
  late final RxDouble _ratio;
  double? _maxWidth;
  bool? altLayoutCache;
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
      if (altLayoutCache ?? false) widget.onCollapse?.call();
      altLayoutCache = false;
      return TitleBarWrapper(child: widget.left);
    }
    altLayoutCache = true;
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
