import 'dart:async';
import 'dart:io';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:bluebubbles/helpers/helpers.dart';
// it does actually export (Web only)
// ignore: undefined_hidden_name
import 'package:bluebubbles/database/models.dart' hide PlayerState;
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class AudioPlayer extends StatefulWidget {
  final PlatformFile file;
  final Attachment? attachment;
  final String? transcript;
  final ConversationViewController? controller;

  const AudioPlayer({
    super.key,
    required this.file,
    required this.attachment,
    this.transcript,
    this.controller,
  });

  @override
  State<StatefulWidget> createState() => _createState();

  State<StatefulWidget> _createState() {
    if (kIsDesktop) return _DesktopAudioPlayerState();
    return _AudioPlayerState();
  }
}

class _AudioPlayerState extends State<AudioPlayer> with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  Attachment? get attachment => widget.attachment;

  PlatformFile get file => widget.file;

  ConversationViewController? get cvController => widget.controller;

  PlayerController? controller;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  late final animController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400), animationBehavior: AnimationBehavior.preserve);
  final playerState = Rx<PlayerState?>(null);
  final maxDuration = 0.obs;

  @override
  void initState() {
    super.initState();
    if (attachment != null) controller = cvController?.audioPlayers[attachment!.guid];
    initBytes();
  }

  @override
  void dispose() {
    controller?.removeListener(_updateMaxDuration);
    _playerStateSubscription?.cancel();
    if (attachment == null) {
      controller?.dispose();
    }
    animController.dispose();
    super.dispose();
  }

  void _updateMaxDuration() {
    maxDuration.value = controller!.maxDuration;
  }

  void initBytes() async {
    if (attachment != null) controller = cvController?.audioPlayers[attachment!.guid];
    final isNewPlayer = controller == null;
    controller ??= PlayerController();
    controller!.addListener(_updateMaxDuration);
    _playerStateSubscription = controller!.onPlayerStateChanged.listen((event) {
      if ((controller!.playerState == PlayerState.paused || controller!.playerState == PlayerState.stopped) &&
          animController.value > 0) {
        animController.reverse();
      }
      playerState.value = controller!.playerState;
    });
    if (isNewPlayer) {
      await controller!.preparePlayer(path: file.path!);
      if (attachment != null) cvController?.audioPlayers[attachment!.guid!] = controller!;
    }
    playerState.value = controller?.playerState;
    maxDuration.value = controller?.maxDuration ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
        padding: const EdgeInsets.all(5),
        child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(
            children: [
              IconButton(
                onPressed: () async {
                  if (controller == null) return;
                  if (playerState.value == PlayerState.playing) {
                    animController.reverse();
                    await controller!.pausePlayer();
                  } else {
                    animController.forward();
                    controller!.setFinishMode(finishMode: FinishMode.pause);
                    await controller!.startPlayer();
                  }
                },
                icon: AnimatedIcon(
                  icon: AnimatedIcons.play_pause,
                  progress: animController,
                ),
                color: context.theme.colorScheme.onSurfaceVariant,
                visualDensity: VisualDensity.compact,
              ),
              Obx(() => maxDuration.value == 0
                  ? SizedBox(width: NavigationSvc.width(context) * 0.25)
                  : AudioFileWaveforms(
                      size: Size(NavigationSvc.width(context) * 0.20, 40),
                      playerController: controller!,
                      padding: EdgeInsets.zero,
                      playerWaveStyle: PlayerWaveStyle(
                          fixedWaveColor: context.theme.colorScheme.surfaceContainerHighest.oppositeLightenOrDarken(20),
                          liveWaveColor: context.theme.colorScheme.onSurfaceVariant,
                          waveCap: StrokeCap.square,
                          waveThickness: 2,
                          seekLineThickness: 2,
                          showSeekLine: false),
                    )),
              const SizedBox(width: 5),
              Expanded(
                child: Center(
                  heightFactor: 1,
                  child: Obx(() => Text(prettyDuration(Duration(milliseconds: maxDuration.value)),
                      style: context.theme.textTheme.labelLarge!)),
                ),
              ),
            ],
          ),
          if (widget.transcript != null)
            Padding(
              padding: const EdgeInsets.only(top: 5, left: 10, right: 10, bottom: 5),
              child: Text(
                "${widget.transcript}",
                style: context.theme.textTheme.bodySmall,
              ),
            ),
        ]));
  }

  @override
  bool get wantKeepAlive => true;
}

class _DesktopAudioPlayerState extends State<AudioPlayer>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  Attachment? get attachment => widget.attachment;

  PlatformFile get file => widget.file;

  ConversationViewController? get cvController => widget.controller;

  Player? controller;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;
  late final animController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 400), animationBehavior: AnimationBehavior.preserve);
  final isPlaying = false.obs;
  final position = Duration.zero.obs;
  final duration = Duration.zero.obs;

  @override
  void initState() {
    super.initState();
    if (attachment != null) controller = cvController?.audioPlayersDesktop[attachment!.guid];
    initBytes();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    if (attachment == null) {
      controller?.dispose();
    }
    animController.dispose();
    super.dispose();
  }

  void initBytes() async {
    if (attachment != null) controller = cvController?.audioPlayersDesktop[attachment!.guid];
    final isNewPlayer = controller == null;
    final player = controller ??= Player();
    _positionSubscription = player.stream.position.listen((pos) => position.value = pos);
    _durationSubscription = player.stream.duration.listen((dur) => duration.value = dur);
    _playingSubscription = player.stream.playing.listen((playing) => isPlaying.value = playing);
    _completedSubscription = player.stream.completed.listen((completed) {
      if (completed) animController.reverse();
    });
    if (isNewPlayer) {
      // Rewinding is player state, so it lives with the cached player rather than any one row.
      player.stream.completed.listen((completed) async {
        if (!completed) return;
        await player.seek(Duration.zero);
        if (Platform.isLinux) await player.pause();
      });
      await player.setPlaylistMode(PlaylistMode.none);
      await player.open(Media(file.path!), play: false);
      if (attachment != null) cvController?.audioPlayersDesktop[attachment!.guid!] = player;
    }
    isPlaying.value = controller?.state.playing ?? false;
    position.value = controller?.state.position ?? Duration.zero;
    duration.value = controller?.state.duration ?? Duration.zero;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
        padding: const EdgeInsets.all(5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () async {
                if (controller == null) return;
                if (isPlaying.value) {
                  animController.reverse();
                  await controller!.pause();
                } else {
                  animController.forward();
                  await controller!.play();
                }
              },
              icon: AnimatedIcon(
                icon: AnimatedIcons.play_pause,
                progress: animController,
              ),
              color: context.theme.colorScheme.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
            ),
            if (controller != null)
              Obx(() => SizedBox(
                    height: 30,
                    child: Slider(
                      value: position.value.inSeconds.toDouble(),
                      onChanged: (double value) {
                        controller!.seek(Duration(seconds: value.toInt()));
                      },
                      min: 0,
                      max: duration.value.inSeconds.toDouble(),
                    ),
                  )),
            Obx(() => Padding(
                  padding: const EdgeInsets.only(left: 10, right: 16),
                  child: Text("${prettyDuration(position.value)} / ${prettyDuration(duration.value)}"),
                ))
          ],
        ));
  }

  @override
  bool get wantKeepAlive => true;
}
