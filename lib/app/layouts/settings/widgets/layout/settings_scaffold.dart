import 'package:bluebubbles/app/components/bb_back_button.dart';
import 'package:bluebubbles/app/components/m3e/m3e_motion.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/wrappers/bb_app_bar.dart';
import 'package:bluebubbles/app/wrappers/bb_scaffold.dart';
import 'package:bluebubbles/app/wrappers/scrollbar_wrapper.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide BackButton;
import 'package:get/get.dart';

import 'settings_header.dart';

class SettingsBackButton extends StatelessWidget {
  const SettingsBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    return BBBackButton(
      style: IconButton.styleFrom(
        backgroundColor: scheme.surfaceContainerHigh,
        foregroundColor: scheme.onSurfaceVariant,
        fixedSize: const Size(48, 48),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      icon: const Icon(Icons.arrow_back),
    );
  }
}

class SettingsScaffold extends StatefulWidget {
  final String title;
  final String? initialHeader;
  final TextStyle? iosSubtitle;
  final TextStyle? materialSubtitle;
  final Color headerColor;
  final Color tileColor;
  final List<Widget> bodySlivers;
  final List<Widget> actions;
  final Widget? stickyPrefix;
  final Widget? stickySuffix;
  final Widget? fab;
  final Widget? leading;
  final bool minimalAppBar;

  const SettingsScaffold({
    super.key,
    required this.title,
    required this.initialHeader,
    required this.iosSubtitle,
    required this.materialSubtitle,
    required this.headerColor,
    required this.tileColor,
    required this.bodySlivers,
    this.actions = const [],
    this.stickyPrefix,
    this.stickySuffix,
    this.fab,
    this.leading,
    this.minimalAppBar = false,
  });

  @override
  State<SettingsScaffold> createState() => _SettingsScaffoldState();
}

class _SettingsScaffoldState extends State<SettingsScaffold> {
  final ScrollController controller = ScrollController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  bool get _expressiveMaterial => SettingsSvc.settings.skin.value == Skins.Material;

  bool get _minimalMaterial => _expressiveMaterial && widget.minimalAppBar;

  bool get _expressiveSamsung => SettingsSvc.settings.skin.value == Skins.Samsung;

  bool get extend => widget.actions.isNotEmpty && kIsDesktop;

  @override
  Widget build(BuildContext context) {
    final scaffoldSw = Stopwatch()..start();
    WidgetsBinding.instance.addPostFrameCallback((_) {});

    final widgetTree = BBScaffold(
      backgroundColor: widget.headerColor,
      appBar: SettingsSvc.settings.skin.value == Skins.Samsung || _expressiveMaterial
          ? null
          : BBAppBar(
              titleText: widget.title,
              leading: widget.leading ?? const BackButton(),
              backgroundColor: widget.headerColor,
              toolbarHeight: extend ? 80 : 50,
              actions: widget.actions,
            ),
      floatingActionButton: widget.fab,
      extendBodyBehindAppBar: false,
      safeAreaTop: _minimalMaterial,
      body: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          if (SettingsSvc.settings.skin.value != Skins.Samsung || kIsWeb || kIsDesktop) return false;
          final scrollDistance = context.height / 3 - 57;
          if (controller.offset > 0 &&
              controller.offset < scrollDistance &&
              controller.offset != controller.position.maxScrollExtent) {
            final double snapOffset = controller.offset / scrollDistance > 0.5 ? scrollDistance : 0;

            final reduceMotion = MediaQuery.disableAnimationsOf(context);
            Future.microtask(() {
              if (reduceMotion) {
                controller.jumpTo(snapOffset);
              } else {
                controller.animateTo(snapOffset,
                    duration: M3EMotion.spatialDefault.duration, curve: M3EMotion.spatialDefault.curve);
              }
            });
          }
          return false;
        },
        child: ScrollbarWrapper(
          showScrollbar: kIsDesktop || kIsWeb,
          controller: controller,
          child: Column(
            children: [
              widget.stickyPrefix ?? const SizedBox.shrink(),
              Expanded(
                child: Obx(
                  () {
                    final listSw = Stopwatch()..start();
                    final view = CustomScrollView(
                      controller: controller,
                      shrinkWrap: true,
                      physics: ThemeSwitcher.getScrollPhysics(),
                      slivers: <Widget>[
                        if (_minimalMaterial)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4, top: 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: widget.leading ?? const BackButton(),
                              ),
                            ),
                          ),
                        if (_expressiveMaterial && !widget.minimalAppBar)
                          SliverAppBar(
                            title: Text(
                              widget.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.theme.textTheme.titleLarge
                                  ?.copyWith(color: context.theme.colorScheme.onSurface),
                            ),
                            leading: Padding(
                              padding: const EdgeInsets.only(left: 24),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: widget.leading ?? const SettingsBackButton(),
                              ),
                            ),
                            leadingWidth: 64,
                            titleSpacing: 22,
                            toolbarHeight: 64,
                            actions: widget.actions,
                            actionsPadding: const EdgeInsets.only(right: 8),
                            backgroundColor: widget.headerColor,
                            surfaceTintColor: Colors.transparent,
                            elevation: 0,
                            scrolledUnderElevation: 0,
                            pinned: true,
                            automaticallyImplyLeading: false,
                          ),
                        if (SettingsSvc.settings.skin.value == Skins.Samsung)
                          SliverAppBar(
                            backgroundColor: widget.headerColor,
                            pinned: true,
                            stretch: true,
                            expandedHeight: context.height / 3,
                            elevation: 0,
                            automaticallyImplyLeading: false,
                            flexibleSpace: LayoutBuilder(
                              builder: (context, _) {
                                var expandRatio = 1 - (controller.offset) / (context.height / 3 - 50);
                                if (expandRatio > 1.0) expandRatio = 1.0;
                                if (expandRatio < 0.1) expandRatio = 0.0;
                                final animation = AlwaysStoppedAnimation<double>(expandRatio);

                                return Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    FadeTransition(
                                      opacity: Tween(begin: 0.0, end: 1.0).animate(CurvedAnimation(
                                        parent: animation,
                                        curve: Interval(0.3, 1.0,
                                            curve: _expressiveSamsung ? M3EMotion.spatialDefault.curve : Curves.easeIn),
                                      )),
                                      child: Center(
                                          child: Text(widget.title,
                                              style: context.theme.textTheme.displaySmall!.copyWith(
                                                  color: context.theme.colorScheme.onSurface,
                                                  fontWeight: _expressiveSamsung ? FontWeight.w700 : null),
                                              textAlign: TextAlign.center)),
                                    ),
                                    FadeTransition(
                                      opacity: Tween(begin: 1.0, end: 0.0).animate(CurvedAnimation(
                                        parent: animation,
                                        curve: Interval(0.0, 0.7,
                                            curve:
                                                _expressiveSamsung ? M3EMotion.spatialDefault.curve : Curves.easeOut),
                                      )),
                                      child: Align(
                                        alignment: Alignment.bottomLeft,
                                        child: Container(
                                          padding: const EdgeInsets.only(left: 50),
                                          height: 50,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              widget.title,
                                              style: context.theme.textTheme.titleLarge,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 8.0),
                                      child: Align(
                                        alignment: Alignment.bottomLeft,
                                        child: SizedBox(
                                          height: 50,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: widget.leading ?? const BackButton(),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Align(
                                      alignment: Alignment.bottomRight,
                                      child: SizedBox(
                                        height: 50,
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: widget.actions,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                          ),
                        if (_expressiveMaterial && widget.initialHeader != null)
                          SliverToBoxAdapter(
                            child: SettingsHeader(
                              iosSubtitle: widget.iosSubtitle,
                              materialSubtitle: widget.materialSubtitle,
                              text: widget.initialHeader!,
                            ),
                          ),
                        if (!_expressiveMaterial &&
                            SettingsSvc.settings.skin.value != Skins.Samsung &&
                            widget.initialHeader != null)
                          SliverToBoxAdapter(
                            child: Container(
                                height: 50,
                                alignment: Alignment.bottomLeft,
                                color: SettingsSvc.settings.skin.value == Skins.iOS ? widget.headerColor : widget.tileColor,
                                child: Padding(
                                  padding: EdgeInsets.only(
                                      bottom: 8.0, left: SettingsSvc.settings.skin.value == Skins.iOS ? 30 : 15),
                                  child: Text(widget.initialHeader!.psCapitalize,
                                      style: SettingsSvc.settings.skin.value == Skins.iOS
                                          ? widget.iosSubtitle
                                          : widget.materialSubtitle),
                                )),
                          ),
                        if (SettingsSvc.settings.skin.value == Skins.Samsung)
                          SliverLayoutBuilder(
                            builder: (context, startConstraints) {
                              final minHeight = context.height -
                                  50 -
                                  context.mediaQueryPadding.top -
                                  context.mediaQueryViewPadding.top;
                              return SliverMainAxisGroup(
                                slivers: [
                                  ...widget.bodySlivers,
                                  SliverLayoutBuilder(
                                    builder: (context, endConstraints) {
                                      final bodyHeight =
                                          endConstraints.precedingScrollExtent - startConstraints.precedingScrollExtent;
                                      // Keep short pages tall enough for the Samsung header to collapse.
                                      return SliverToBoxAdapter(
                                        child: SizedBox(
                                          height: (minHeight - bodyHeight).clamp(0.0, double.infinity),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              );
                            },
                          )
                        else
                          ...widget.bodySlivers,
                        SliverToBoxAdapter(
                          child: Container(
                            height: 30,
                          ),
                        ),
                      ],
                    );
                    listSw.stop();
                    return view;
                  },
                ),
              ),
              widget.stickySuffix ?? const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
    scaffoldSw.stop();
    return widgetTree;
  }
}
