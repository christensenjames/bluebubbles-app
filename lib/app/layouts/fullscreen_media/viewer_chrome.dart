import 'package:bluebubbles/app/layouts/fullscreen_media/dialogs/metadata_dialog.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;

abstract interface class ViewerPageActions {
  void download();
  void shareFile();
  void refreshAttachment();
  VoidCallback? get enterPip;
}

RectTween viewerHeroRectTween(Rect? begin, Rect? end) => RectTween(begin: begin, end: end);

enum _MenuAction { info, redownload, pip }

class ViewerChrome extends StatelessWidget {
  const ViewerChrome({
    super.key,
    required this.visible,
    required this.attachment,
    required this.showActions,
    required this.currentPage,
  });

  static const double barHeight = 48;

  final bool visible;
  final Attachment attachment;
  final bool showActions;
  final ViewerPageActions? Function() currentPage;

  static Widget _button(IconData icon, String tooltip, VoidCallback onPressed) => IconButton(
    icon: Icon(icon),
    iconSize: 24,
    color: Colors.white,
    tooltip: tooltip,
    style: IconButton.styleFrom(fixedSize: const Size.square(barHeight)),
    onPressed: onPressed,
  );

  Widget _title(BuildContext context) {
    final message = attachment.message.target;
    final name = (message?.isFromMe ?? false) ? 'You' : message?.handleRelation.target?.displayName ?? 'Unknown';
    final created = message?.dateCreated;
    final date = created == null ? null : intl.DateFormat('EEE').add_jm().format(created);
    final textTheme = Theme.of(context).textTheme;
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 150),
        layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
        child: Column(
          key: ValueKey('$name|$date'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium!.copyWith(color: Colors.white),
            ),
            if (date != null)
              Text(date, maxLines: 1, style: textTheme.bodySmall!.copyWith(color: Colors.white.withValues(alpha: 0.7))),
          ],
        ),
      ),
    );
  }

  Widget _overflowMenu(BuildContext context) => PopupMenuButton<_MenuAction>(
    icon: const Icon(Icons.more_vert),
    iconSize: 24,
    iconColor: Colors.white,
    padding: EdgeInsets.zero,
    style: IconButton.styleFrom(fixedSize: const Size.square(barHeight)),
    onSelected: (action) {
      switch (action) {
        case _MenuAction.info:
          showMetadataDialog(attachment, context);
        case _MenuAction.redownload:
          currentPage()?.refreshAttachment();
        case _MenuAction.pip:
          currentPage()?.enterPip?.call();
      }
    },
    itemBuilder: (context) => [
      const PopupMenuItem(value: _MenuAction.info, child: Text('Info')),
      const PopupMenuItem(value: _MenuAction.redownload, child: Text('Re-download')),
      if (currentPage()?.enterPip != null)
        const PopupMenuItem(value: _MenuAction.pip, child: Text('Picture-in-picture')),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _ChromeBar(
            visible: visible,
            top: true,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
                child: SizedBox(
                  height: barHeight,
                  child: Row(
                    children: [
                      _button(
                        Icons.arrow_back,
                        MaterialLocalizations.of(context).backButtonTooltip,
                        () => Navigator.of(context).maybePop(),
                      ),
                      if (showActions) ...[
                        Expanded(
                          child: Padding(padding: const EdgeInsets.only(left: 4), child: _title(context)),
                        ),
                        _overflowMenu(context),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        if (showActions)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _ChromeBar(
              visible: visible,
              top: false,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 0),
                  child: SizedBox(
                    height: barHeight,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (!kIsWeb && !kIsDesktop)
                          _button(Icons.share_outlined, 'Share', () => currentPage()?.shareFile()),
                        _button(Icons.download_outlined, 'Download', () => currentPage()?.download()),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChromeBar extends StatelessWidget {
  const _ChromeBar({required this.visible, required this.top, required this.child});

  final bool visible;
  final bool top;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return IgnorePointer(
      ignoring: !visible,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: visible ? 1 : 0),
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
        curve: visible ? Easing.standard : Easing.standardAccelerate,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * (top ? -8 : 8)), child: child),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                      end: top ? Alignment.bottomCenter : Alignment.topCenter,
                      colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
