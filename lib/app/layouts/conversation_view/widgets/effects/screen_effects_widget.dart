import 'dart:async';
import 'dart:math';

import 'package:bluebubbles/app/animations/balloon_classes.dart';
import 'package:bluebubbles/app/animations/balloon_rendering.dart';
import 'package:bluebubbles/app/animations/celebration_class.dart';
import 'package:bluebubbles/app/animations/celebration_rendering.dart';
import 'package:bluebubbles/app/animations/fireworks_classes.dart';
import 'package:bluebubbles/app/animations/fireworks_rendering.dart';
import 'package:bluebubbles/app/animations/laser_classes.dart';
import 'package:bluebubbles/app/animations/laser_rendering.dart';
import 'package:bluebubbles/app/animations/love_classes.dart';
import 'package:bluebubbles/app/animations/love_rendering.dart';
import 'package:bluebubbles/app/animations/spotlight_classes.dart';
import 'package:bluebubbles/app/animations/spotlight_rendering.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ScreenEffectsWidget extends StatefulWidget {
  const ScreenEffectsWidget({super.key});

  @override
  State<StatefulWidget> createState() {
    return _ScreenEffectsWidgetState();
  }
}

class _ScreenEffectsWidgetState extends State<ScreenEffectsWidget> with TickerProviderStateMixin {
  late final FireworkController fireworkController;
  late final CelebrationController celebrationController;
  late final ConfettiController confettiController;
  late final BalloonController balloonController;
  late final LoveController loveController;
  late final SpotlightController spotlightController;
  late final LaserController laserController;
  late final StreamSubscription<dynamic> _eventSubscription;
  bool _initialized = false;
  String screenSelected = "";

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      fireworkController =
          FireworkController(vsync: this, windowSize: Size(NavigationSvc.width(context), context.height));
      celebrationController =
          CelebrationController(vsync: this, windowSize: Size(NavigationSvc.width(context), context.height));
      confettiController = ConfettiController(duration: const Duration(seconds: 1));
      balloonController =
          BalloonController(vsync: this, windowSize: Size(NavigationSvc.width(context), context.height));
      loveController = LoveController(vsync: this, windowSize: Size(NavigationSvc.width(context), context.height));
      spotlightController =
          SpotlightController(vsync: this, windowSize: Size(NavigationSvc.width(context), context.height));
      laserController = LaserController(vsync: this, windowSize: Size(NavigationSvc.width(context), context.height));
      _initialized = true;
    });

    _eventSubscription = EventDispatcherSvc.stream.listen((event) async {
      if (event.type == 'play-effect' && mounted && screenSelected.isEmpty) {
        setState(() {
          screenSelected = event.data['type'];
        });
        final rect = event.data['size'];
        if (screenSelected == "fireworks" && !fireworkController.isPlaying) {
          fireworkController.windowSize = Size(NavigationSvc.width(context), context.height);
          fireworkController.start();
          await Future.delayed(const Duration(seconds: 1));
          if (!mounted) return;
          fireworkController.stop(onStop: () {
            setState(() {
              screenSelected = "";
            });
          });
        } else if (screenSelected == "celebration" && !celebrationController.isPlaying) {
          celebrationController.windowSize = Size(NavigationSvc.width(context), context.height);
          celebrationController.start();
          await Future.delayed(const Duration(seconds: 1));
          if (!mounted) return;
          celebrationController.stop(onStop: () {
            setState(() {
              screenSelected = "";
            });
          });
        } else if (screenSelected == "balloons" && !balloonController.isPlaying) {
          balloonController.windowSize = Size(NavigationSvc.width(context), context.height);
          balloonController.start();
          await Future.delayed(const Duration(seconds: 1));
          if (!mounted) return;
          balloonController.stop(onStop: () {
            setState(() {
              screenSelected = "";
            });
          });
        } else if (screenSelected == "love" && !loveController.isPlaying) {
          if (rect != null) {
            loveController.windowSize = Size(NavigationSvc.width(context), context.height);
            loveController.start(Point((rect!.left + rect!.right) / 2, (rect!.top + rect!.bottom) / 2));
            await Future.delayed(const Duration(seconds: 1));
            if (!mounted) return;
            loveController.stop(onStop: () {
              setState(() {
                screenSelected = "";
              });
            });
          }
        } else if (screenSelected == "spotlight" && !spotlightController.isPlaying) {
          if (rect != null) {
            spotlightController.windowSize = Size(NavigationSvc.width(context), context.height);
            spotlightController.start(rect!);
            await Future.delayed(const Duration(seconds: 1));
            if (!mounted) return;
            spotlightController.stop(onStop: () {
              setState(() {
                screenSelected = "";
              });
            });
          }
        } else if (screenSelected == "lasers" && !laserController.isPlaying) {
          if (rect != null) {
            laserController.windowSize = Size(NavigationSvc.width(context), context.height);
            laserController.start(rect!);
            await Future.delayed(const Duration(seconds: 1));
            if (!mounted) return;
            laserController.stop(onStop: () {
              setState(() {
                screenSelected = "";
              });
            });
          }
        } else if (screenSelected == "confetti") {
          confettiController.play();
          await Future.delayed(const Duration(seconds: 1));
          if (!mounted) return;
          screenSelected = "";
        }
      }
    });
  }

  @override
  void dispose() {
    _eventSubscription.cancel();
    if (_initialized) {
      confettiController.dispose();
      // An effect's ticker exists only while it plays; finished effects already disposed theirs.
      if (fireworkController.isPlaying) fireworkController.dispose();
      if (celebrationController.isPlaying) celebrationController.dispose();
      if (balloonController.isPlaying) balloonController.dispose();
      if (loveController.isPlaying) loveController.dispose();
      if (spotlightController.isPlaying) spotlightController.dispose();
      if (laserController.isPlaying) laserController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      color: screenSelected == "fireworks" ||
              screenSelected == "celebration" ||
              screenSelected == "spotlight" ||
              screenSelected == "lasers"
          ? Colors.black
          : Colors.transparent,
      child: screenSelected.isEmpty
          ? null
          : Stack(children: [
              Fireworks(controller: fireworkController),
              Celebration(controller: celebrationController),
              Balloons(controller: balloonController),
              Love(controller: loveController),
              Spotlight(controller: spotlightController),
              Laser(controller: laserController),
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: confettiController,
                  blastDirection: pi / 2,
                  blastDirectionality: BlastDirectionality.explosive,
                  emissionFrequency: 0.35,
                ),
              ),
            ]),
    );
  }
}
