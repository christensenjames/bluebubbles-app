import 'dart:async';
import 'dart:math';

import 'package:bluebubbles/app/components/m3e/m3e_motion.dart';
import 'package:bluebubbles/app/layouts/conversation_details/dialogs/timeframe_picker.dart';
import 'package:bluebubbles/app/state/message_state.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:faker/faker.dart' show faker;
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

class ScheduledMessages extends StatefulWidget {
  const ScheduledMessages({super.key, required this.chatGuid});

  final String chatGuid;

  @override
  State<ScheduledMessages> createState() => _ScheduledMessagesState();
}

enum _Panel { none, actions, confirm }

class _ScheduledMessagesState extends State<ScheduledMessages> {
  Set<int>? _initialIds;
  int? _openId;
  bool _confirming = false;
  // Cancelled items stay on screen after the server drops them, until their exit animation finishes.
  final Map<int, ScheduledMessage> _leaving = {};

  void _show(int id, _Panel panel) => setState(() {
    _openId = panel == _Panel.none ? null : id;
    _confirming = panel == _Panel.confirm;
  });

  void _setLeaving(ScheduledMessage item, bool leaving) {
    if (leaving) {
      _leaving[item.id] = item;
    } else {
      setState(() {
        _leaving.remove(item.id);
        if (_openId == item.id) _openId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: M3EMotion.spatialFast.durationOf(context),
      curve: M3EMotion.spatialFast.curve,
      alignment: Alignment.topCenter,
      child: Obx(() {
        final pending = ScheduledMsgsSvc.pendingFor(widget.chatGuid);
        final items = [...pending, ..._leaving.values.where((item) => !pending.any((p) => p.id == item.id))]
          ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
        final initialIds = _initialIds ??= {for (final item in items) item.id};
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in items)
              _ScheduledMessageBubble(
                key: ValueKey(item.id),
                item: item,
                arrive: !initialIds.contains(item.id),
                panel: item.id != _openId
                    ? _Panel.none
                    : _confirming
                    ? _Panel.confirm
                    : _Panel.actions,
                onPanel: (panel) => _show(item.id, panel),
                onLeaving: (leaving) => _setLeaving(item, leaving),
              ),
          ],
        );
      }),
    );
  }
}

class _ScheduledMessageBubble extends StatefulWidget {
  const _ScheduledMessageBubble({
    super.key,
    required this.item,
    required this.arrive,
    required this.panel,
    required this.onPanel,
    required this.onLeaving,
  });

  final ScheduledMessage item;
  final bool arrive;
  final _Panel panel;
  final ValueChanged<_Panel> onPanel;
  final ValueChanged<bool> onLeaving;

  @override
  State<_ScheduledMessageBubble> createState() => _ScheduledMessageBubbleState();
}

class _ScheduledMessageBubbleState extends State<_ScheduledMessageBubble> with TickerProviderStateMixin, ThemeHelpers {
  static const _exitDuration = Duration(milliseconds: 180);

  late final AnimationController _arrive = AnimationController(
    vsync: this,
    duration: M3EMotion.spatialFast.duration,
    value: widget.arrive ? 0 : 1,
  );
  late final AnimationController _exit = AnimationController(vsync: this, duration: _exitDuration);
  late final String _fakeText = faker.lorem.words(item.payload.message.split(" ").length).join(" ");
  Timer? _dueTimer;
  bool _busy = false;

  ScheduledMessage get item => widget.item;

  @override
  void initState() {
    super.initState();
    if (widget.arrive) _arrive.forward();
    _watchDue();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _arrive.matchReducedMotion(context, M3EMotion.spatialFast.duration);
    _exit.matchReducedMotion(context, _exitDuration);
  }

  @override
  void didUpdateWidget(_ScheduledMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.scheduledFor != item.scheduledFor) _watchDue();
  }

  @override
  void dispose() {
    _dueTimer?.cancel();
    _arrive.dispose();
    _exit.dispose();
    super.dispose();
  }

  void _watchDue() {
    _dueTimer?.cancel();
    final left = item.scheduledFor.difference(DateTime.now());
    if (!left.isNegative) _dueTimer = Timer(left, () => setState(() {}));
  }

  Future<void> _editTime() async {
    final date = await showTimeframePicker("Pick date and time", context, presetsAhead: true);
    // The send time may have passed while the picker was open; the server is sending it now.
    if (date == null || !mounted || !item.scheduledFor.isAfter(DateTime.now())) return;
    if (!date.isAfter(DateTime.now())) {
      return showSnackbar("Error", "Pick a date in the future!", type: SnackbarType.error);
    }
    setState(() => _busy = true);
    final updated = await ScheduledMsgsSvc.update(item, date: date);
    if (!mounted) return;
    setState(() => _busy = false);
    if (updated == null) {
      showSnackbar(
        "Error",
        "Couldn't change the time. Check the server connection and try again.",
        type: SnackbarType.error,
      );
    } else {
      widget.onPanel(_Panel.none);
    }
  }

  Future<void> _cancel() async {
    setState(() => _busy = true);
    widget.onLeaving(true);
    final deleted = await ScheduledMsgsSvc.delete(item);
    if (!mounted) return;
    if (deleted) {
      await _exit.forward();
      if (mounted) widget.onLeaving(false);
      return;
    }
    widget.onLeaving(false);
    setState(() => _busy = false);
    showSnackbar(
      "Error",
      "Couldn't cancel the message. Check the server connection and try again.",
      type: SnackbarType.error,
    );
  }

  static String _dayAndTime(DateTime date) {
    final now = DateTime.now();
    final time = buildTime(date);
    // UTC dates so a DST change between today and the send day can't shift the day count.
    final days = DateTime.utc(
      date.year,
      date.month,
      date.day,
    ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
    if (days == 0) return "Today $time";
    if (days < 7) return "${DateFormat.E().format(date)} $time";
    if (date.year == now.year) return "${DateFormat.MMMd().format(date)} $time";
    return "${DateFormat.yMMMd().format(date)} $time";
  }

  static String _repeat(Schedule schedule, DateTime next) {
    final interval = schedule.interval ?? 1;
    if (interval == 1 && schedule.intervalType == "weekly") return "${DateFormat.E().format(next)} ${buildTime(next)}";
    if (interval == 1 && schedule.intervalType == "daily") return "day ${buildTime(next)}";
    final unit = frequencyToText[schedule.intervalType] ?? schedule.intervalType;
    return "${interval == 1 ? unit : "$interval ${unit}s"} · ${_dayAndTime(next)}";
  }

  Widget _panel(ColorScheme colors, _Panel panel) {
    final textTheme = context.theme.textTheme;
    final children = switch (panel) {
      _Panel.none => const <Widget>[],
      _Panel.actions => [
        TextButton.icon(
          style: _chipStyle(colors),
          onPressed: _busy ? null : _editTime,
          icon: Icon(iOS ? CupertinoIcons.calendar : Icons.edit_calendar_outlined),
          label: const Text("Edit time"),
        ),
        TextButton.icon(
          style: _chipStyle(colors),
          onPressed: _busy ? null : () => widget.onPanel(_Panel.confirm),
          icon: Icon(iOS ? CupertinoIcons.xmark : Icons.close),
          label: const Text("Cancel"),
        ),
      ],
      _Panel.confirm => [
        Text("Cancel this message?", style: textTheme.bodyMedium!.copyWith(color: colors.onSurfaceVariant)),
        TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            textStyle: textTheme.labelLarge,
          ),
          onPressed: _busy ? null : () => widget.onPanel(_Panel.none),
          child: const Text("Keep"),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: colors.onError,
            minimumSize: const Size(0, 32),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: textTheme.labelLarge,
          ),
          onPressed: _busy ? null : _cancel,
          child: const Text("Cancel message"),
        ),
      ],
    };
    if (children.isEmpty) return const SizedBox.shrink(key: ValueKey(_Panel.none));
    // A padded tap target already adds the gap above the row.
    final padded = context.theme.materialTapTargetSize == MaterialTapTargetSize.padded;
    return Padding(
      key: ValueKey(panel),
      padding: EdgeInsets.only(top: padded ? 0 : 8),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        children: children,
      ),
    );
  }

  ButtonStyle _chipStyle(ColorScheme colors) => TextButton.styleFrom(
    backgroundColor: colors.surfaceContainerHighest,
    foregroundColor: colors.onSurface,
    iconColor: colors.onSurfaceVariant,
    iconSize: 18,
    minimumSize: const Size(0, 32),
    padding: const EdgeInsets.fromLTRB(10, 0, 14, 0),
    textStyle: context.theme.textTheme.labelLarge,
  );

  @override
  Widget build(BuildContext context) {
    final colors = context.theme.colorScheme;
    final screenWidth = NavigationSvc.width(context);
    final radius = material ? 20.0 : 22.0;
    final recurring = item.schedule.type == "recurring";
    final due = !item.scheduledFor.isAfter(DateTime.now());
    final when = due ? "" : (recurring ? _repeat(item.schedule, item.scheduledFor) : _dayAndTime(item.scheduledFor));
    final caption = due ? "Sending…" : (recurring ? "Every $when" : "Sends $when");
    final spoken = due ? "sending now" : (recurring ? "sends every $when" : "sends $when");
    // Past due, the server is sending it: editing or cancelling now would race that send.
    final panel = due && !_busy ? _Panel.none : widget.panel;
    // Non-Material sent bubbles keep 10px on their right for the tail, so the edge lines up with theirs.
    final edge = EdgeInsets.only(right: material ? 0 : 10);
    void open(_Panel next) {
      if (!_busy) widget.onPanel(next);
    }

    final bubble = Obx(() {
      final redact = SettingsSvc.settings.redactedMode.value && SettingsSvc.settings.hideMessageContent.value;
      final text = redact ? _fakeText : item.payload.message;
      return Semantics(
        container: true,
        button: !due,
        expanded: panel != _Panel.none,
        label: "Scheduled message: $text, $spoken",
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
            onTap: due ? null : () => open(panel == _Panel.none ? _Panel.actions : _Panel.none),
            onSecondaryTap: !due && (kIsDesktop || kIsWeb) ? () => open(_Panel.actions) : null,
            child: ExcludeSemantics(
              child: CustomPaint(
                painter: _DashedOutlinePainter(color: colors.primary, radius: radius),
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: material
                        ? screenWidth * MessageState.materialBubbleSizeFactor
                        : screenWidth * MessageState.maxBubbleSizeFactor - 50,
                    minHeight: 36,
                  ),
                  padding: EdgeInsets.symmetric(vertical: 8, horizontal: material ? 16 : 15),
                  child: Center(
                    widthFactor: 1,
                    child: RichText(
                      text: TextSpan(
                        children: MessageHelper.buildEmojiText(
                          text,
                          context.theme.extension<BubbleText>()!.bubbleText.apply(color: colors.onSurface),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });

    final captionStyle = context.theme.textTheme.labelSmall!.copyWith(
      color: colors.primary,
      fontWeight: FontWeight.w600,
    );
    final content = AnimatedOpacity(
      opacity: _busy ? 0.6 : 1,
      duration: M3EMotion.effectsFast.durationOf(context),
      curve: M3EMotion.effectsFast.curve,
      child: Padding(
        padding: EdgeInsets.only(top: 8, left: material ? 8 : 5, right: material ? 8 : 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Padding(padding: edge, child: bubble),
            ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      recurring
                          ? (iOS ? CupertinoIcons.repeat : Icons.repeat)
                          : (iOS ? CupertinoIcons.clock : Icons.schedule_outlined),
                      size: 14,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(caption, style: captionStyle),
                  ],
                ),
              ),
            ),
            Padding(
              padding: edge,
              child: AnimatedSwitcher(
                duration: M3EMotion.effectsFast.durationOf(context),
                switchInCurve: M3EMotion.effectsFast.curve,
                switchOutCurve: M3EMotion.effectsFast.curve,
                layoutBuilder: (current, previous) =>
                    Stack(alignment: AlignmentDirectional.topEnd, children: [...previous, ?current]),
                child: _panel(colors, panel),
              ),
            ),
          ],
        ),
      ),
    );

    return AnimatedBuilder(
      animation: Listenable.merge([_arrive, _exit]),
      builder: (context, child) {
        final arrived = Easing.emphasizedDecelerate.transform(_arrive.value);
        final gone = Easing.standard.transform(_exit.value);
        return Opacity(
          opacity: (0.01 + 0.99 * arrived) * (1 - gone),
          child: Transform.translate(
            offset: Offset(0, 28 * (1 - arrived)),
            child: Transform.scale(scale: (0.96 + 0.04 * arrived) * (1 - 0.04 * gone), child: child),
          ),
        );
      },
      child: content,
    );
  }
}

class _DashedOutlinePainter extends CustomPainter {
  const _DashedOutlinePainter({required this.color, required this.radius});

  static const _stroke = 1.5;
  static const _dash = 4.5;
  static const _gap = 3.0;

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(_stroke / 2);
    final path = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(min(radius, rect.shortestSide / 2))));
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke;
    for (final metric in path.computeMetrics()) {
      // A whole number of dash periods, so the outline closes without a short dash at the seam.
      final count = max(1, (metric.length / (_dash + _gap)).round());
      final period = metric.length / count;
      final dash = period * _dash / (_dash + _gap);
      for (var i = 0; i < count; i++) {
        canvas.drawPath(metric.extractPath(i * period, i * period + dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedOutlinePainter oldDelegate) => oldDelegate.color != color || oldDelegate.radius != radius;
}
