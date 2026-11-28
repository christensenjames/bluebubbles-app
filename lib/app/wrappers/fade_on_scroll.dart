import 'package:flutter/material.dart';

class FadeOnScroll extends StatefulWidget {
  final ScrollController scrollController;
  final double zeroOpacityOffset;
  final double fullOpacityOffset;
  final Widget child;

  const FadeOnScroll(
      {super.key,
      required this.scrollController,
      required this.child,
      this.zeroOpacityOffset = 0,
      this.fullOpacityOffset = 0});

  @override
  State<StatefulWidget> createState() => _FadeOnScrollState();
}

class _FadeOnScrollState extends State<FadeOnScroll> {
  late double _offset;

  @override
  initState() {
    super.initState();
    if (widget.scrollController.positions.length > 1) {
      _offset = 0;
    } else {
      _offset = widget.scrollController.offset;
    }
    widget.scrollController.addListener(_setOffset);
  }

  @override
  dispose() {
    widget.scrollController.removeListener(_setOffset);
    super.dispose();
  }

  void _setOffset() {
    final offset = widget.scrollController.offset;
    final opacityChanged = _calculateOpacity(offset) != _calculateOpacity(_offset);
    if (opacityChanged) {
      setState(() => _offset = offset);
    } else {
      _offset = offset;
    }
  }

  double _calculateOpacity(double offset) {
    if (widget.fullOpacityOffset == widget.zeroOpacityOffset) {
      return 1;
    } else if (widget.fullOpacityOffset > widget.zeroOpacityOffset) {
      // fading in
      if (offset <= widget.zeroOpacityOffset) {
        return 0;
      } else if (offset >= widget.fullOpacityOffset) {
        return 1;
      } else {
        return (offset - widget.zeroOpacityOffset) / (widget.fullOpacityOffset - widget.zeroOpacityOffset);
      }
    } else {
      // fading out
      if (offset <= widget.fullOpacityOffset) {
        return 1;
      } else if (offset >= widget.zeroOpacityOffset) {
        return 0;
      } else {
        return (offset - widget.zeroOpacityOffset) / (widget.fullOpacityOffset - widget.zeroOpacityOffset);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: _calculateOpacity(_offset),
      child: widget.child,
    );
  }
}
