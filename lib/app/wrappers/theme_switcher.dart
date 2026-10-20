import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/components/custom/custom_cupertino_page_transition.dart';
import 'package:bluebubbles/app/components/custom/custom_bouncing_scroll_physics.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ThemeSwitcher extends StatefulWidget {
  const ThemeSwitcher({super.key, required this.iOSSkin, required this.materialSkin, this.samsungSkin});
  final Widget iOSSkin;
  final Widget materialSkin;
  final Widget? samsungSkin;

  static PageRoute<T> buildPageRoute<T>(
      {required Widget Function(BuildContext context) builder, bool instantPush = false}) {
    switch (SettingsSvc.settings.skin.value) {
      case Skins.iOS:
        return PageRouteBuilder<T>(
            transitionDuration: instantPush ? Duration.zero : const Duration(milliseconds: 300),
            pageBuilder: (context, animation, secondaryAnimation) => builder.call(context),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return CustomCupertinoPageTransition(
                  primaryRouteAnimation: animation, linearTransition: false, child: child);
            });
      case Skins.Material:
      case Skins.Samsung:
        return instantPush
            ? _InstantPushMaterialPageRoute<T>(builder: builder)
            : MaterialPageRoute<T>(builder: builder);
    }
  }

  static PageRoute<T> buildTransparentPageRoute<T>({required Widget Function(BuildContext context) builder}) {
    return PageRouteBuilder<T>(
      opaque: false,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      pageBuilder: (context, animation, secondaryAnimation) => builder.call(context),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    );
  }

  static ScrollPhysics getScrollPhysics() {
    switch (SettingsSvc.settings.skin.value) {
      case Skins.iOS:
        return const AlwaysScrollableScrollPhysics(
          parent: CustomBouncingScrollPhysics(),
        );
      case Skins.Material:
        return const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        );
      case Skins.Samsung:
        return const AlwaysScrollableScrollPhysics(
          parent: ClampingScrollPhysics(),
        );
    }
  }

  @override
  State<ThemeSwitcher> createState() => _ThemeSwitcherState();
}

class _ThemeSwitcherState extends State<ThemeSwitcher> with ThemeHelpers {
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      switch (SettingsSvc.settings.skin.value) {
        case Skins.iOS:
          return widget.iOSSkin;
        case Skins.Material:
          return widget.materialSkin;
        case Skins.Samsung:
          return widget.samsungSkin ?? widget.materialSkin;
      }
    });
  }
}

class _InstantPushMaterialPageRoute<T> extends MaterialPageRoute<T> {
  _InstantPushMaterialPageRoute({required super.builder});

  bool _pushed = false;

  @override
  Duration get transitionDuration => _pushed ? super.transitionDuration : Duration.zero;

  // A zero-duration push completes synchronously; later forwards, like cancelling a back swipe, need the real duration.
  @override
  TickerFuture didPush() {
    final TickerFuture push = super.didPush();
    _pushed = true;
    controller!.duration = transitionDuration;
    return push;
  }
}
