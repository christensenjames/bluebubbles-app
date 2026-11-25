import 'package:bluebubbles/app/components/circle_progress_bar.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/fullscreen_image.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/fullscreen_video.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/viewer_chrome.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/zoomable_media.dart';
import 'package:bluebubbles/models/models.dart' show MessageReplyContext;
import 'package:bluebubbles/app/wrappers/bb_app_bar.dart';
import 'package:bluebubbles/app/wrappers/bb_scaffold.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/app/wrappers/titlebar_wrapper.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import "package:flutter/material.dart";
import 'package:flutter/services.dart';
import 'package:get/get.dart';

class ConversationFullscreenHolder extends StatefulWidget {
  const ConversationFullscreenHolder(
      {super.key,
      required this.attachment,
      required this.showInteractions,
      this.currentChat,
      this.videoController,
      this.mute,
      this.initialAttachmentGuid,
      this.replyMessage,
      this.replyPartIndex,
      this.galleryAttachments,
      this.onOpenCollectionGallery});

  final Chat? currentChat;
  final Attachment attachment;
  final bool showInteractions;
  final VideoController? videoController;
  final RxBool? mute;
  final String? initialAttachmentGuid;
  final Message? replyMessage;
  final int? replyPartIndex;

  /// When non-null, the fullscreen carousel is limited to these attachments
  /// instead of all images in the chat (a media collection, or a filtered gallery).
  final List<Attachment>? galleryAttachments;

  static String heroTagFor(Attachment attachment) =>
      'attachment-hero-${attachment.message.target?.guid}-${attachment.guid}';
  /// When set, shows a grid button that opens the enclosing media collection's gallery
  /// (see `MediaCollection.openGallery`). Called with this screen's context.
  final void Function(BuildContext context)? onOpenCollectionGallery;

  @override
  ConversationFullscreenHolderState createState() => ConversationFullscreenHolderState();
}

class ConversationFullscreenHolderState extends State<ConversationFullscreenHolder> with ThemeHelpers {
  static const double _seekBarZoneFraction = 0.25;

  final focusNode = FocusNode();
  late final PageController controller;
  late final messageService = widget.currentChat == null ? null : maybeFindMessagesSvc(widget.currentChat!.guid);

  /// Explicit list, else chat-wide images.
  List<Attachment>? get _scopedGallery => widget.galleryAttachments;

  late List<Attachment> attachments = _scopedGallery != null
      ? List<Attachment>.from(_scopedGallery!)
      : (widget.currentChat == null
          ? [attachment]
          : (messageService?.struct.attachments.where((e) => e.mimeStart == "image").toList() ?? [attachment]));

  int currentIndex = 0;
  ScrollPhysics? physics;
  final ValueNotifier<double> _dismissProgress = ValueNotifier(0);
  final Map<int, GlobalKey> _pageKeys = {};

  VideoController? _inlineController;

  // media_kit_video_controls' seek/volume/brightness GestureDetector always registers a
  // non-null onHorizontalDragUpdate regardless of the `seekGesture` theme flag (only its
  // callback body checks the flag, not whether the recognizer is attached). As a descendant
  // of the PageView, that recognizer wins the gesture arena's "eager winner" race before
  // PageView's own drag recognizer ever gets a chance, permanently blocking swipe on any
  // video page. Since that's vendored package behavior we can't patch, drive the page controller
  // from raw pointer tracking (which never enters the arena) whenever the current page is a video.
  // Excludes touches starting in the bottom quarter of the screen so dragging the video's own seek
  // bar isn't misread as a page swipe.
  int? _videoSwipePointer;
  Offset? _videoSwipeSlopStart;
  Drag? _videoSwipeDrag;
  VelocityTracker? _videoSwipeVelocityTracker;
  bool _dismissDragging = false;

  Attachment get attachment => widget.attachment;
  // Start hidden for video (video auto-plays and manages its own overlay); show for images
  bool get _isVideoAttachment => attachment.mimeStart == "video";
  late bool showAppBar = kIsDesktop || kIsWeb || !_isVideoAttachment;
  bool get _canReply => widget.replyMessage != null && widget.replyPartIndex != null && widget.currentChat != null;
  bool get _hasCollectionGallery => widget.onOpenCollectionGallery != null;

  void _openCollectionGallery() {
    widget.onOpenCollectionGallery!(context);
  }

  GlobalKey _pageKey(int index) => _pageKeys.putIfAbsent(index, GlobalKey.new);

  ViewerPageActions? _currentPage() {
    final state = _pageKeys[currentIndex]?.currentState;
    if (state case final ViewerPageActions actions) return actions;
    return null;
  }

  void _setOverlay(bool show) {
    if (showAppBar == show) return;
    setState(() => showAppBar = show);
    if (material) _applySystemUi();
  }

  void _applySystemUi() =>
      SystemChrome.setEnabledSystemUIMode(showAppBar ? SystemUiMode.edgeToEdge : SystemUiMode.immersive);

  void _onDismissProgress(double progress) {
    _dismissProgress.value = progress;
    // A downward drag can drift sideways; the PageView must not take it over mid-dismiss.
    if ((progress > 0) != _dismissDragging) setState(() => _dismissDragging = progress > 0);
  }

  void _dismiss() => Navigator.of(context).pop();

  void _resetVideoSwipe() {
    _videoSwipePointer = null;
    _videoSwipeSlopStart = null;
    _videoSwipeDrag = null;
    _videoSwipeVelocityTracker = null;
  }

  void _turnPage({required bool forward}) {
    if (MediaQuery.disableAnimationsOf(context)) {
      final target = currentIndex + (forward ? 1 : -1);
      if (target >= 0 && target < attachments.length) controller.jumpToPage(target);
    } else if (forward) {
      controller.nextPage(duration: Durations.medium2, curve: Easing.emphasizedDecelerate);
    } else {
      controller.previousPage(duration: Durations.medium2, curve: Easing.emphasizedDecelerate);
    }
  }

  Widget _withChrome(Widget viewer) {
    if (!material) return viewer;
    final fadeBackground = ModalRoute.of(context)?.opaque == false;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          ValueListenableBuilder<double>(
            valueListenable: _dismissProgress,
            builder: (context, progress, _) =>
                ColoredBox(color: Colors.black.withValues(alpha: fadeBackground ? 1 - progress : 1)),
          ),
          viewer,
          ValueListenableBuilder<double>(
            valueListenable: _dismissProgress,
            builder: (context, progress, _) => ViewerChrome(
              visible: showAppBar && progress == 0,
              attachment: attachments[currentIndex],
              showActions: widget.showInteractions,
              currentPage: _currentPage,
              onOpenCollectionGallery: _hasCollectionGallery ? _openCollectionGallery : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _inlineController = widget.videoController;
    if (kIsWeb || !widget.showInteractions) {
      controller = PageController(initialPage: 0);
    } else {
      if (widget.currentChat != null || _scopedGallery != null) {
        final targetGuid = widget.initialAttachmentGuid ?? attachment.guid;
        currentIndex = attachments.indexWhere((e) => e.guid == targetGuid);
        if (currentIndex == -1 && widget.currentChat != null) {
          attachments.add(attachment);
          currentIndex = attachments.indexWhere((e) => e.guid == attachment.guid);
        }
        if (currentIndex == -1) currentIndex = 0;
      }
      controller = PageController(initialPage: currentIndex);
    }
    if (material) _applySystemUi();
  }

  @override
  void dispose() {
    focusNode.dispose();
    controller.dispose();
    _dismissProgress.dispose();
    if (material) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void triggerReply() {
      if (!_canReply) return;
      final selectedAttachment = attachments[currentIndex];
      cvc(widget.currentChat!).replyToMessage = MessageReplyContext(
        widget.replyMessage!,
        widget.replyPartIndex!,
        attachmentGuid: selectedAttachment.guid,
      );
      Navigator.of(context).pop();
    }

    return TitleBarWrapper(
      child: Actions(
        actions: {
          GoBackIntent: GoBackAction(context),
        },
        child: BBScaffold(
          safeAreaLeft: false,
          safeAreaRight: false,
          extendBodyBehindAppBar: true,
          extendBodyBehindBottomPill: true,
          appBar: !iOS || !showAppBar
              ? null
              : BBAppBar(
                  leading: TextButton(
                    child: Text("Done",
                        style: context.theme.textTheme.bodyLarge!.copyWith(color: context.theme.colorScheme.primary)),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  ),
                  leadingWidth: 75,
                  titleText: kIsWeb || !widget.showInteractions || widget.currentChat == null
                      ? "Media"
                      : "${currentIndex + 1} of ${attachments.length}",
                  titleStyle:
                      context.theme.textTheme.titleLarge!.copyWith(color: context.theme.colorScheme.onSurfaceVariant),
                  iconTheme: IconThemeData(color: context.theme.colorScheme.primary),
                  actions: [
                    if (_hasCollectionGallery)
                      IconButton(
                        onPressed: _openCollectionGallery,
                        icon: Icon(iOS ? CupertinoIcons.square_grid_2x2 : Icons.grid_view_outlined),
                      ),
                    if (_canReply)
                      IconButton(
                        tooltip: "Reply",
                        onPressed: triggerReply,
                        icon: const Icon(CupertinoIcons.reply),
                      ),
                  ],
                  backgroundColor: context.theme.colorScheme.surfaceContainerHighest,
                ),
          backgroundColor: material ? Colors.transparent : Colors.black,
          body: _withChrome(FocusScope(
            child: Focus(
              focusNode: focusNode,
              autofocus: true,
              onKeyEvent: (node, event) {
                Logger.info(
                    "Got device label ${event.deviceType.label}, physical key ${event.physicalKey.toString()}, logical key ${event.logicalKey.toString()}",
                    tag: "RawKeyboardListener");
                if (event is KeyUpEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                  _turnPage(forward: SettingsSvc.settings.fullscreenViewerSwipeDir.value != SwipeDirection.RIGHT);
                } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                  _turnPage(forward: SettingsSvc.settings.fullscreenViewerSwipeDir.value != SwipeDirection.LEFT);
                } else if (event.logicalKey == LogicalKeyboardKey.escape) {
                  // Swallow repeats too, or they reach the app-wide Escape shortcut and close the chat.
                  if (event is KeyDownEvent && ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (event) {
                  if (attachments.length < 2 || attachments[currentIndex].mimeStart != "video") return;
                  // Leave the bottom quarter (seek bar / controls) alone.
                  if (event.position.dy > MediaQuery.sizeOf(context).height * (1 - _seekBarZoneFraction)) return;
                  _videoSwipePointer = event.pointer;
                  _videoSwipeSlopStart = event.position;
                  _videoSwipeVelocityTracker = VelocityTracker.withKind(event.kind)
                    ..addPosition(event.timeStamp, event.position);
                },
                onPointerMove: (event) {
                  if (_videoSwipePointer != event.pointer) return;
                  _videoSwipeVelocityTracker!.addPosition(event.timeStamp, event.position);
                  final slopStart = _videoSwipeSlopStart;
                  if (slopStart != null) {
                    final moved = event.position - slopStart;
                    if (moved.distance < kTouchSlop) return;
                    _videoSwipeSlopStart = null;
                    // A mostly vertical drag never pages; it belongs to swipe-down-to-close.
                    if (moved.dx.abs() <= moved.dy.abs()) {
                      _resetVideoSwipe();
                      return;
                    }
                    _videoSwipeDrag = controller.position.drag(
                      DragStartDetails(globalPosition: event.position, kind: event.kind),
                      () => _videoSwipeDrag = null,
                    );
                    return;
                  }
                  _videoSwipeDrag?.update(DragUpdateDetails(
                    globalPosition: event.position,
                    delta: Offset(event.delta.dx, 0),
                    primaryDelta: event.delta.dx,
                    sourceTimeStamp: event.timeStamp,
                  ));
                },
                onPointerUp: (event) {
                  if (_videoSwipePointer != event.pointer) return;
                  final velocity = _videoSwipeVelocityTracker!.getVelocity().clampMagnitude(0, kMaxFlingVelocity);
                  final dx = velocity.pixelsPerSecond.dx;
                  // The page settles from where the finger left it, carrying the release velocity.
                  _videoSwipeDrag?.end(DragEndDetails(
                    velocity: Velocity(pixelsPerSecond: Offset(dx, 0)),
                    primaryVelocity: dx,
                  ));
                  _resetVideoSwipe();
                },
                onPointerCancel: (event) {
                  if (_videoSwipePointer != event.pointer) return;
                  _videoSwipeDrag?.cancel();
                  _resetVideoSwipe();
                },
                child: PageView.builder(
                physics: _dismissDragging
                    ? const NeverScrollableScrollPhysics()
                    : physics ??
                        (attachments.length == 1
                            ? const NeverScrollableScrollPhysics()
                            : ThemeSwitcher.getScrollPhysics()),
                reverse: SettingsSvc.settings.fullscreenViewerSwipeDir.value == SwipeDirection.RIGHT,
                itemCount: attachments.length,
                onPageChanged: (int val) {
                  PipSvc.setAutoEnter(enabled: false);
                  setState(() {
                    currentIndex = val;
                    // Reset a zoom-lock (NeverScrollableScrollPhysics) set by the page we're
                    // leaving — FullscreenImage's PhotoView reports its own scale state via
                    // updatePhysics, but `physics` lives on this shared holder, not per-page.
                    // Without this reset, landing on a video (which never calls updatePhysics)
                    // after a zoomed image permanently locks the PageView from then on.
                    physics = null;
                  });
                },
                controller: controller,
                itemBuilder: (BuildContext context, int index) {
                  final attachment = attachments[index];
                  dynamic content = AttachmentsSvc.getContent(attachment,
                      path: attachment.guid == null ? attachment.transferName : null);
                  final key = attachment.guid ?? attachment.transferName ?? randomString(8);

                  if (content is PlatformFile) {
                    if (attachment.mimeStart == "image") {
                      return HeroMode(
                        enabled: index == currentIndex && !MediaQuery.disableAnimationsOf(context),
                        child: FullscreenImage(
                          key: material ? _pageKey(index) : Key(key),
                          attachment: attachment,
                          file: content,
                          showInteractions: widget.showInteractions,
                          onOpenCollectionGallery: _hasCollectionGallery ? _openCollectionGallery : null,
                          updatePhysics: (ScrollPhysics p) {
                            if (physics != p) {
                              setState(() {
                                physics = p;
                              });
                            }
                          },
                          onOverlayToggle: _setOverlay,
                          onTap: material ? () => _setOverlay(!showAppBar) : null,
                          onDismissProgress: _onDismissProgress,
                          onDismiss: _dismiss,
                          heroTag: material ? ConversationFullscreenHolder.heroTagFor(attachment) : null,
                        ),
                      );
                    } else if (attachment.mimeStart == "video") {
                      return SwipeToDismiss(
                        ignoredBottomFraction: _seekBarZoneFraction,
                        onDismissProgress: _onDismissProgress,
                        onDismiss: _dismiss,
                        child: FullscreenVideo(
                          key: material ? _pageKey(index) : Key(key),
                          file: content,
                          attachment: attachment,
                          showInteractions: widget.showInteractions,
                          videoController: attachment.guid == widget.attachment.guid ? _inlineController : null,
                          mute: widget.mute,
                          isCurrentPage: index == currentIndex,
                          sharedChrome: material,
                          onOpenCollectionGallery: _hasCollectionGallery ? _openCollectionGallery : null,
                          onOverlayToggle: (show) {
                            if (material && index != currentIndex) return;
                            _setOverlay(show);
                          },
                          onPlayerDetached: () {
                            _inlineController = null;
                          },
                        ),
                      );
                    } else {
                      return const SizedBox.shrink();
                    }
                  } else if (content is Attachment) {
                    final Attachment _content = content;
                    return InkWell(
                      onTap: () {
                        setState(() {
                          content = AttachmentDownloader.startDownload(content, onComplete: (file) {
                            setState(() {
                              content = file;
                            });
                          });
                        });
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SizedBox(
                            height: 40,
                            width: 40,
                            child: Center(
                                child: Icon(iOS ? CupertinoIcons.cloud_download : Icons.cloud_download_outlined,
                                    size: 30)),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            (_content.mimeType ?? ""),
                            style: context.theme.textTheme.bodyLarge!
                                .copyWith(color: context.theme.colorScheme.onSurfaceVariant),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _content.getFriendlySize(),
                            style: context.theme.textTheme.bodyMedium!
                                .copyWith(color: context.theme.colorScheme.onSurfaceVariant),
                            maxLines: 1,
                          ),
                        ],
                      ),
                    );
                  } else if (content is AttachmentDownloadController) {
                    final AttachmentDownloadController _content = content;
                    return InkWell(
                      onTap: () {
                        final AttachmentDownloadController _content = content;
                        if (_content.state.value != AttachmentDownloadState.error) return;
                        content = AttachmentDownloader.startDownload(_content.attachment, onComplete: (file) {
                          setState(() {
                            content = file;
                          });
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Obx(() {
                          final isError = _content.state.value == AttachmentDownloadState.error;
                          final isProcessing = _content.state.value == AttachmentDownloadState.processing;
                          final isQueued = _content.state.value == AttachmentDownloadState.queued;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              SizedBox(
                                height: 40,
                                width: 40,
                                child: Center(
                                  child: isError
                                      ? Icon(iOS ? CupertinoIcons.arrow_clockwise : Icons.refresh, size: 30)
                                      : isProcessing
                                          ? (iOS
                                              ? const CupertinoActivityIndicator(radius: 14)
                                              : const CircularProgressIndicator())
                                          : isQueued
                                              ? Icon(iOS ? CupertinoIcons.clock : Icons.schedule, size: 30)
                                              : CircleProgressBar(
                                                  value: _content.progress.value?.toDouble() ?? 0,
                                                  backgroundColor: context.theme.colorScheme.outline,
                                                  foregroundColor: context.theme.colorScheme.onSurfaceVariant,
                                                ),
                                ),
                              ),
                              isError ? const SizedBox(height: 10) : const SizedBox(height: 5),
                              Text(
                                isError
                                    ? "Failed to download!"
                                    : isProcessing
                                        ? "Processing"
                                        : isQueued
                                            ? "Queued"
                                            : (_content.attachment.mimeType ?? ""),
                                style: context.theme.textTheme.bodyLarge!
                                    .copyWith(color: context.theme.colorScheme.onSurfaceVariant),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              )
                            ],
                          );
                        }),
                      ),
                    );
                  } else {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Error loading attachment",
                          style: context.theme.textTheme.bodyLarge,
                        ),
                      ],
                    );
                  }
                },
                ),
              ),
            ),
          )),
        ),
      ),
    );
  }
}
