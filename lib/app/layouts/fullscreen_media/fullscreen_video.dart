import 'dart:async';

import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/utils/share.dart';
import 'package:flutter/scheduler.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/dialogs/metadata_dialog.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';

//ignore: implementation_imports
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit_video/media_kit_video_controls/media_kit_video_controls.dart' as media_kit_video_controls;
import 'package:universal_html/html.dart' as html;

class FullscreenVideo extends StatefulWidget {
  const FullscreenVideo({
    super.key,
    required this.file,
    required this.attachment,
    required this.showInteractions,
    this.videoController,
    this.onPlayerDetached,
    this.mute,
    this.onOverlayToggle,
    this.isCurrentPage = true,
  });

  final PlatformFile file;
  final Attachment attachment;
  final bool showInteractions;

  final VideoController? videoController;
  final VoidCallback? onPlayerDetached;
  final RxBool? mute;
  final Function(bool)? onOverlayToggle;
  final bool isCurrentPage;

  @override
  State<StatefulWidget> createState() => _FullscreenVideoState();
}

class _FullscreenVideoState extends State<FullscreenVideo> with AutomaticKeepAliveClientMixin, ThemeHelpers {
  static const _speeds = [1.0, 1.5, 2.0, 0.5];
  static bool? _sessionMuted;

  Timer? hideOverlayTimer;

  late VideoController videoController;
  bool _ownsPlayer = false;

  bool hasListener = false;
  bool hasDisposed = false;
  Offset? _pointerDownPosition;
  Duration _pointerDownTime = Duration.zero;
  Offset _lastTapPosition = Offset.zero;
  Timer? _singleTapTimer;
  bool _secondTap = false;
  Timer? _autoplayTimer;
  bool _mediaReady = false;
  int _refreshCount = 0;
  double? _volumeBeforeMute;
  StreamSubscription<double>? _volumeSub;
  StreamSubscription<bool>? _completedSub;
  StreamSubscription<bool>? _playingSub;
  bool _pipSupported = false;
  StreamSubscription<bool>? _pipPlayingSub;
  StreamSubscription<void>? _pipDismissedSub;
  Worker? _pipActiveWorker;
  GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  final FocusNode _keyFocus = FocusNode(debugLabel: 'FullscreenVideo shortcuts');
  late final RxBool muted =
      (widget.mute?.value ?? _sessionMuted ?? SettingsSvc.settings.startVideosMutedFullscreen.value).obs;
  final RxBool showPlayPauseOverlay = true.obs;
  final RxDouble aspectRatio = 1.0.obs;

  @override
  void initState() {
    super.initState();

    _setFullscreen(true);
    initControllers();
    if (kIsDesktop && widget.isCurrentPage) _keyFocus.requestFocus();
  }

  @override
  void didUpdateWidget(FullscreenVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrentPage && !oldWidget.isCurrentPage) {
      if (kIsDesktop) _keyFocus.requestFocus();
      if (!kIsDesktop && !kIsWeb && _mediaReady) _scheduleAutoplay();
      if (_pipSupported) {
        PipSvc.setAutoEnter(
          enabled: videoController.player.state.playing,
          aspectRatio: videoController.aspectRatio,
        );
      }
    } else if (!widget.isCurrentPage && oldWidget.isCurrentPage) {
      _autoplayTimer?.cancel();
      videoController.player.pause();
    }
  }

  void _scheduleAutoplay() {
    _autoplayTimer?.cancel();
    // The delay lets the viewer finish appearing before playback starts.
    _autoplayTimer = Timer(const Duration(milliseconds: 500), () {
      if (!hasDisposed && widget.isCurrentPage && _mediaReady) videoController.player.play();
    });
  }

  void _setFullscreen(bool fullscreen) {
    if (fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  void initControllers() async {
    _ownsPlayer = widget.videoController == null;
    videoController = widget.videoController ?? VideoController(Player());
    final controller = videoController;
    final refreshCount = _refreshCount;
    if (!_ownsPlayer) {
      await controller.player.setVolume(muted.value ? 0 : 100);
    } else {
      late final Media media;
      if (widget.file.path == null) {
        final blob = html.Blob([widget.file.bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        media = Media(url);
      } else {
        media = Media(widget.file.path!);
      }

      await controller.player.setPlaylistMode(PlaylistMode.none);
      if (hasDisposed || controller != videoController) return;
      await controller.player.open(media, play: false);
      if (hasDisposed || controller != videoController) return;
      await controller.player.setVolume(muted.value ? 0 : 100);
    }

    if (hasDisposed || controller != videoController) return;
    await _attachPlayer();
    if (hasDisposed || controller != videoController) return;

    if (!kIsDesktop && !kIsWeb) {
      // Start with all overlays hidden
      showPlayPauseOverlay.value = false;
      widget.onOverlayToggle?.call(false);
      // A refresh during the awaits above leaves the old media open; its own completion marks the new media ready.
      if (refreshCount == _refreshCount) {
        _mediaReady = true;
        _scheduleAutoplay();
      }
    } else {
      showPlayPauseOverlay.value = true;
    }

    if (widget.showInteractions && await PipSvc.isSupported() && !hasDisposed && controller == videoController) {
      _pipSupported = true;
      _subscribeToPipPlayback();
      _pipDismissedSub = PipSvc.dismissed.listen((_) {
        if (!mounted || !widget.isCurrentPage || ModalRoute.of(context)?.isCurrent != true) return;
        videoController.player.pause();
        Navigator.of(context).pop();
      });
      _pipActiveWorker = ever<bool>(PipSvc.active, (active) {
        if (hasDisposed) return;
        _cancelHideTimer();
        showPlayPauseOverlay.value = false;
        widget.onOverlayToggle?.call(false);
      });
    }

    if (hasDisposed) return;
    setState(() {});
  }

  Future<void> _attachPlayer() async {
    _volumeSub = videoController.player.stream.volume.listen((volume) => muted.value = volume == 0);
    createListener(videoController);
    if (_pipSupported) _subscribeToPipPlayback();
    await _configureAndroidVideoColorPipeline(videoController.player);
  }

  void _detachPlayer() {
    _volumeSub?.cancel();
    _completedSub?.cancel();
    _playingSub?.cancel();
    _pipPlayingSub?.cancel();
    videoController.rect.removeListener(_updateAspectRatio);
    hasListener = false;
  }

  void _subscribeToPipPlayback() {
    _pipPlayingSub = videoController.player.stream.playing.listen((playing) {
      if (widget.isCurrentPage) {
        PipSvc.setAutoEnter(enabled: playing, aspectRatio: videoController.aspectRatio);
      }
    });
    if (widget.isCurrentPage) {
      PipSvc.setAutoEnter(
        enabled: videoController.player.state.playing,
        aspectRatio: videoController.aspectRatio,
      );
    }
  }

  void _updateAspectRatio() {
    aspectRatio.value = videoController.aspectRatio;
  }

  Future<void> _configureAndroidVideoColorPipeline(Player player) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    final platform = player.platform;
    if (platform is! NativePlayer) return;

    try {
      // Force conservative HDR->SDR conversion for iPhone HDR clips, which can
      // otherwise appear over-bright on some Android GPU + mpv combinations.
      for (final (name, value) in const [
        ('target-colorspace-hint', 'yes'),
        ('target-prim', 'bt.709'),
        ('target-trc', 'srgb'),
        ('tone-mapping', 'hable'),
        ('target-peak', '203'),
        ('hdr-compute-peak', 'no'),
      ]) {
        if (hasDisposed || player != videoController.player) return;
        await platform.setProperty(name, value);
      }
    } catch (e, s) {
      Logger.error('FullscreenVideo: Failed to apply Android video color pipeline!', error: e, trace: s);
    }
  }

  void createListener(VideoController controller) {
    if (hasListener) return;

    controller.rect.addListener(_updateAspectRatio);

    _completedSub = controller.player.stream.completed.listen((completed) async {
      if (hasDisposed || controller != videoController) return;
      // If the status is ended, restart
      if (completed && controller.player.state.playlistMode == PlaylistMode.none) {
        await controller.player.pause();
        if (hasDisposed || controller != videoController) return;
        await controller.player.seek(Duration.zero);
        if (hasDisposed || controller != videoController) return;
        await controller.player.pause();
        if (hasDisposed || controller != videoController) return;
        _cancelHideTimer();
        showPlayPauseOverlay.value = true;
        showPlayPauseOverlay.refresh();
        widget.onOverlayToggle?.call(true);
      }
    });

    _playingSub = controller.player.stream.playing.listen((playing) {
      if (hasDisposed || controller != videoController || kIsDesktop || kIsWeb) return;
      if (playing) {
        // Only start the hide timer if the overlays are currently visible
        if (showPlayPauseOverlay.value) {
          _startHideTimer();
        }
      } else {
        // Video paused — always show all overlays
        _cancelHideTimer();
        showPlayPauseOverlay.value = true;
        widget.onOverlayToggle?.call(true);
      }
    });

    hasListener = true;
  }

  void _cancelHideTimer() {
    hideOverlayTimer?.cancel();
    hideOverlayTimer = null;
  }

  void _startHideTimer() {
    _cancelHideTimer();
    hideOverlayTimer = Timer(const Duration(seconds: 3), () {
      if (!hasDisposed) {
        showPlayPauseOverlay.value = false;
        widget.onOverlayToggle?.call(false);
      }
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (kIsDesktop) _keyFocus.requestFocus();
    if (kIsDesktop || kIsWeb) return;
    _pointerDownPosition = event.position;
    _pointerDownTime = event.timeStamp;
    _secondTap = (_singleTapTimer?.isActive ?? false) && (event.position - _lastTapPosition).distance < kDoubleTapSlop;
    if (_secondTap) _singleTapTimer!.cancel();
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (kIsDesktop || kIsWeb) return;
    final downPosition = _pointerDownPosition;
    if (downPosition == null) return;
    _pointerDownPosition = null;
    // Tap-to-toggle ignores showInteractions; that flag only gates the action buttons.
    final isTap =
        (downPosition - event.position).distance < 20 && event.timeStamp - _pointerDownTime < kLongPressTimeout;
    if (_secondTap) {
      _secondTap = false;
      // A real double tap is left to media_kit's seek gesture; if the second press was not a tap, commit the first.
      if (!isTap) _toggleOverlay();
      return;
    }
    if (isTap) {
      _lastTapPosition = event.position;
      _singleTapTimer = Timer(kDoubleTapTimeout, _toggleOverlay);
    }
  }

  void _toggleOverlay() {
    final newVal = !showPlayPauseOverlay.value;
    showPlayPauseOverlay.value = newVal;
    widget.onOverlayToggle?.call(newVal);
    if (newVal && videoController.player.state.playing) {
      _startHideTimer();
    } else {
      _cancelHideTimer();
    }
  }

  Future<void> _toggleMute() async {
    final player = videoController.player;
    final mute = !muted.value;
    final volume = player.state.volume;
    if (mute && volume > 0) _volumeBeforeMute = volume;
    _sessionMuted = mute;
    await player.setVolume(mute ? 0 : _volumeBeforeMute ?? 100);
  }

  Future<void> _shareFile() async {
    if (widget.file.path == null) return;
    if (_pipSupported) await PipSvc.setAutoEnter(enabled: false);
    if (hasDisposed) return;
    await videoController.player.pause();
    Share.files([widget.file.path!]);
  }

  void _cycleSpeed() {
    final player = videoController.player;
    player.setRate(_speeds[(_speeds.indexOf(player.state.rate) + 1) % _speeds.length]);
  }

  void _toggleLoop() {
    final player = videoController.player;
    player.setPlaylistMode(player.state.playlistMode == PlaylistMode.single ? PlaylistMode.none : PlaylistMode.single);
  }

  void _seekBy(Duration delta) {
    final player = videoController.player;
    final target = player.state.position + delta;
    final duration = player.state.duration;
    player.seek(target < Duration.zero ? Duration.zero : (target > duration ? duration : target));
  }

  void _changeVolume(double delta) {
    final player = videoController.player;
    player.setVolume((player.state.volume + delta).clamp(0.0, 100.0));
  }

  void _handleEscape() {
    final videoState = _videoKey.currentState;
    if (videoState != null && videoState.isFullscreen()) {
      videoState.exitFullscreen();
    } else if (ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  Map<ShortcutActivator, VoidCallback> _desktopShortcuts() {
    return {
      const SingleActivator(LogicalKeyboardKey.space): () => videoController.player.playOrPause(),
      const SingleActivator(LogicalKeyboardKey.keyK): () => videoController.player.playOrPause(),
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause): () => videoController.player.playOrPause(),
      const SingleActivator(LogicalKeyboardKey.mediaPlay): () => videoController.player.play(),
      const SingleActivator(LogicalKeyboardKey.mediaPause): () => videoController.player.pause(),
      const SingleActivator(LogicalKeyboardKey.keyJ): () => _seekBy(const Duration(seconds: -10)),
      const SingleActivator(LogicalKeyboardKey.keyL): () => _seekBy(const Duration(seconds: 10)),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => _changeVolume(10),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => _changeVolume(-10),
      const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
      const SingleActivator(LogicalKeyboardKey.keyF): () => _videoKey.currentState?.toggleFullscreen(),
      const SingleActivator(LogicalKeyboardKey.escape, includeRepeats: false): _handleEscape,
    };
  }

  @override
  void dispose() {
    hasDisposed = true;
    _cancelHideTimer();
    _singleTapTimer?.cancel();
    _autoplayTimer?.cancel();
    _detachPlayer();
    _pipDismissedSub?.cancel();
    _pipActiveWorker?.dispose();
    _keyFocus.dispose();
    if (_pipSupported && widget.isCurrentPage) PipSvc.setAutoEnter(enabled: false);
    _setFullscreen(false);

    // Sync mute state back to parent — deferred to avoid mutating an Rx value
    // while the widget tree is locked (causes markNeedsBuild error in Obx).
    if (widget.mute != null) {
      final muteValue = muted.value;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        widget.mute!.value = muteValue;
      });
    }

    if (_ownsPlayer) {
      videoController.player.dispose();
    } else {
      // The inline player has no UI for rate or looping.
      videoController.player.setRate(1.0);
      videoController.player.setPlaylistMode(PlaylistMode.none);
    }

    super.dispose();
  }

  Future<void> refreshAttachment() async {
    // A pending autoplay would start the old media, which stays open in an owned player until the download finishes.
    _autoplayTimer?.cancel();
    _mediaReady = false;
    _refreshCount++;
    if (!_ownsPlayer) {
      _detachPlayer();
      widget.onPlayerDetached?.call();
      videoController = VideoController(Player());
      _ownsPlayer = true;
      await videoController.player.setPlaylistMode(PlaylistMode.none);
      if (hasDisposed) return;
      await _attachPlayer();
      if (hasDisposed) return;
      // Video binds its player streams in initState, so it must remount for the new controller.
      setState(() => _videoKey = GlobalKey<VideoState>());
    }
    Future<void> onComplete(PlatformFile file) async {
      if (hasDisposed) return;
      late final Media media;
      if (file.path == null) {
        final blob = html.Blob([file.bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        media = Media(url);
      } else {
        media = Media(file.path!);
      }
      await videoController.player.open(media, play: false);
      if (hasDisposed) return;
      await videoController.player.setVolume(muted.value ? 0 : 100);
      if (hasDisposed) return;
      showPlayPauseOverlay.value = !videoController.player.state.playing;
      _mediaReady = !kIsDesktop && !kIsWeb;
    }
    redownloadAttachmentFromViewer(widget.attachment, onComplete: onComplete);
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final topInset = MediaQuery.paddingOf(context).top;
    final primary = context.theme.colorScheme.primary;
    Widget button(Widget icon, VoidCallback onPressed) => kIsDesktop
        ? media_kit_video_controls.MaterialDesktopCustomButton(icon: icon, onPressed: onPressed)
        : media_kit_video_controls.MaterialCustomButton(icon: icon, onPressed: onPressed);
    final topButtonBar = <Widget>[
      if (!iOS) ...[
        button(const Icon(Icons.close), () => Navigator.of(context).pop()),
        const Spacer(),
        if (widget.showInteractions) ...[
          button(const Icon(Icons.file_download_outlined), () => AttachmentsSvc.saveToDisk(widget.file)),
          if (!kIsWeb && !kIsDesktop) button(const Icon(Icons.share_outlined), _shareFile),
          if (_pipSupported)
            button(
              const Icon(Icons.picture_in_picture_alt_outlined),
              () => PipSvc.enter(aspectRatio: videoController.aspectRatio),
            ),
          button(const Icon(Icons.info_outlined), () => showMetadataDialog(widget.attachment, context)),
          button(const Icon(Icons.refresh), refreshAttachment),
        ],
      ],
    ];
    // The iOS skin's bottom action bar already has a mute button.
    final muteButton = !iOS || !widget.showInteractions
        ? button(Obx(() => Icon(muted.value ? Icons.volume_off : Icons.volume_up)), _toggleMute)
        : null;
    final speedButton = StreamBuilder<double>(
      stream: videoController.player.stream.rate,
      initialData: videoController.player.state.rate,
      builder: (_, snapshot) {
        final rate = snapshot.requireData;
        final label = rate == rate.truncateToDouble() ? rate.toInt().toString() : rate.toString();
        return button(
          Text(
            '${label}x',
            style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          _cycleSpeed,
        );
      },
    );
    final loopButton = StreamBuilder<PlaylistMode>(
      stream: videoController.player.stream.playlistMode,
      initialData: videoController.player.state.playlistMode,
      builder: (_, snapshot) => button(
        Icon(Icons.repeat, color: snapshot.requireData == PlaylistMode.single ? primary : Colors.white),
        _toggleLoop,
      ),
    );
    final video = Obx(
      () => Video(
        key: _videoKey,
        controller: videoController,
        controls: PipSvc.active.value
            ? media_kit_video_controls.NoVideoControls
            : (state) => Padding(
                padding: kIsWeb || kIsDesktop
                    ? const EdgeInsets.fromLTRB(20, 20, 20, 0)
                    : EdgeInsets.only(
                        bottom: iOS && widget.showInteractions ? 100 : MediaQuery.systemGestureInsetsOf(context).bottom),
                child: kIsDesktop
                    ? media_kit_video_controls.MaterialDesktopVideoControls(state)
                    // media_kit's theme never notifies on change (inverted updateShouldNotify); remount when the
                    // inset or the late-arriving PiP button changes.
                    : KeyedSubtree(
                        key: ValueKey((topInset, _pipSupported)),
                        child: media_kit_video_controls.MaterialVideoControls(state),
                      ),
              ),
        filterQuality: FilterQuality.medium,
      ),
    );
    final Widget themedVideo;
    if (kIsDesktop) {
      final shortcuts = _desktopShortcuts();
      final controlsTheme = media_kit_video_controls.kDefaultMaterialDesktopVideoControlsThemeData.copyWith(
        playAndPauseOnTap: true,
        keyboardShortcuts: shortcuts,
        seekBarPositionColor: primary,
        seekBarThumbColor: primary,
        topButtonBar: topButtonBar,
        bottomButtonBar: [
          const media_kit_video_controls.MaterialDesktopPlayOrPauseButton(),
          ?muteButton,
          const media_kit_video_controls.MaterialDesktopPositionIndicator(),
          const Spacer(),
          speedButton,
          loopButton,
          const media_kit_video_controls.MaterialDesktopFullscreenButton(),
        ],
      );
      // media_kit's own shortcut focus only wins in its fullscreen route, so the viewer page carries the
      // bindings too. Left/right stay unbound so they keep paging the gallery.
      themedVideo = CallbackShortcuts(
        bindings: widget.isCurrentPage ? shortcuts : const {},
        child: Focus(
          focusNode: _keyFocus,
          child: media_kit_video_controls.MaterialDesktopVideoControlsTheme(
            normal: controlsTheme,
            // Close would pop media_kit's own fullscreen route without leaving native fullscreen.
            fullscreen: controlsTheme.copyWith(topButtonBar: const []),
            child: video,
          ),
        ),
      );
    } else {
      final controlsTheme = media_kit_video_controls.kDefaultMaterialVideoControlsThemeData.copyWith(
        seekGesture: false,
        seekOnDoubleTap: true,
        speedUpOnLongPress: true,
        topButtonBarMargin: EdgeInsets.fromLTRB(16, topInset, 16, 0),
        seekBarPositionColor: primary,
        seekBarThumbColor: primary,
        // Keeps the seek drag clear of the edge back gestures.
        seekBarMargin: const EdgeInsets.symmetric(horizontal: 16),
        topButtonBar: topButtonBar,
        bottomButtonBar: [
          const media_kit_video_controls.MaterialPositionIndicator(),
          const Spacer(),
          speedButton,
          loopButton,
          ?muteButton,
        ],
      );
      themedVideo = media_kit_video_controls.MaterialVideoControlsTheme(
        normal: controlsTheme,
        fullscreen: controlsTheme,
        child: video,
      );
    }
    return Container(
      color: Colors.black,
      child: Obx(
        () => MouseRegion(
          onEnter: (event) => showPlayPauseOverlay.value = true,
          onExit: (event) => showPlayPauseOverlay.value = !videoController.player.state.playing,
          child: Theme(
            data: context.theme.copyWith(
              platform: iOS ? TargetPlatform.iOS : TargetPlatform.android,
              dialogTheme: context.theme.dialogTheme
                  .copyWith(backgroundColor: context.theme.colorScheme.surfaceContainerHighest),
              iconTheme: context.theme.iconTheme.copyWith(color: context.theme.textTheme.bodyMedium?.color),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handlePointerDown,
                  onPointerUp: _handlePointerUp,
                  child: themedVideo,
                ),
                // Bottom action bar for iOS
                if (iOS && widget.showInteractions)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: AnimatedOpacity(
                      opacity: showPlayPauseOverlay.value ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: SafeArea(
                        top: false,
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: samsung
                                ? Colors.black
                                : context.theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              IconButton(
                                icon: Icon(
                                  CupertinoIcons.cloud_download,
                                  color: samsung ? Colors.white : context.theme.colorScheme.primary,
                                ),
                                onPressed: () => AttachmentsSvc.saveToDisk(widget.file),
                              ),
                              if (!kIsWeb && !kIsDesktop)
                                IconButton(
                                  icon: Icon(
                                    CupertinoIcons.share,
                                    color: context.theme.colorScheme.primary,
                                  ),
                                  onPressed: _shareFile,
                                ),
                              IconButton(
                                icon: Icon(
                                  CupertinoIcons.info,
                                  color: samsung ? Colors.white : context.theme.colorScheme.primary,
                                ),
                                onPressed: () => showMetadataDialog(widget.attachment, context),
                              ),
                              IconButton(
                                icon: Icon(
                                  CupertinoIcons.refresh,
                                  color: samsung ? Colors.white : context.theme.colorScheme.primary,
                                ),
                                onPressed: () => refreshAttachment(),
                              ),
                              IconButton(
                                icon: Icon(
                                  muted.value ? CupertinoIcons.volume_mute : CupertinoIcons.volume_up,
                                  color: samsung ? Colors.white : context.theme.colorScheme.primary,
                                ),
                                onPressed: _toggleMute,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
