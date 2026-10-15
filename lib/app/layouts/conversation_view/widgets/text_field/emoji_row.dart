import 'dart:math' as math;

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';

const List<String> _defaultEmojis = ['😂', '😘', '😀', '❤️', '😭', '😅', '😓', '😔', '😉', '🙏'];

class EmojiRow extends StatefulWidget {
  const EmojiRow({super.key, required this.parentController});

  final ConversationViewController parentController;

  @override
  State<EmojiRow> createState() => _EmojiRowState();
}

class _EmojiRowState extends State<EmojiRow> with WidgetsBindingObserver {
  ConversationViewController get parentController => widget.parentController;
  double _keyboardHeight = 0;

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
  void didChangeMetrics() {
    if (mounted) setState(() {});
  }

  static List<String> getDisplayEmojis(List<String> recents) => {...recents, ..._defaultEmojis}.take(10).toList();

  void _onEmojiTap(String emoji) {
    SettingsSvc.settings.addRecentEmojis([emoji]);
    final tc = parentController.textController;
    final text = tc.text;
    final selection = tc.selection;

    if (!selection.isValid || selection.start > text.length || selection.end > text.length) {
      tc.value = TextEditingValue(
        text: text + emoji,
        selection: TextSelection.collapsed(offset: text.length + emoji.length),
      );
    } else {
      final start = math.min(selection.start, selection.end);
      final end = math.max(selection.start, selection.end);
      final newText = text.replaceRange(start, end, emoji);
      tc.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + emoji.length),
      );
    }
    parentController.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    // The Scaffold strips keyboard insets from its body's MediaQuery, so read the window's own.
    final inset = View.of(context).viewInsets.bottom;
    if (inset <= 0) _keyboardHeight = 0;
    if (!context.material || kIsWeb || !Platform.isAndroid || inset <= 0) {
      return const SizedBox.shrink();
    }
    if (inset > _keyboardHeight) _keyboardHeight = inset;
    // Insets update every frame of the keyboard animation; scaling by them makes the row open and close with it.
    final t = (inset / _keyboardHeight).clamp(0.0, 1.0);

    return Obx(() {
      final emojis = getDisplayEmojis(SettingsSvc.settings.recentEmojis);
      final row = Container(
        height: 44,
        decoration: BoxDecoration(
          color: context.theme.colorScheme.surfaceContainerLow,
          border: Border(
            top: BorderSide(color: context.theme.colorScheme.outlineVariant, width: 1),
            bottom: BorderSide(color: context.theme.colorScheme.outlineVariant, width: 1),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: Row(
            children: [
              for (final emoji in emojis)
                Expanded(
                  child: InkResponse(
                    radius: 20,
                    onTap: () => _onEmojiTap(emoji),
                    child: Center(
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 17),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
      return ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: t,
          child: Opacity(opacity: t, child: row),
        ),
      );
    });
  }
}
