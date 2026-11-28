import 'package:bluebubbles/app/layouts/findmy/findmy_page.dart';
import 'package:bluebubbles/app/layouts/settings/settings_page.dart';
import 'package:bluebubbles/app/wrappers/titlebar_wrapper.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/helpers/types/helpers/misc_helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

// ignore: non_constant_identifier_names
NavigatorService get NavigationSvc =>
    Get.isRegistered<NavigatorService>() ? Get.find<NavigatorService>() : Get.put(NavigatorService());

enum AppSection { settings, findMy }

/// The chat list's split is nested navigators 1 (left) and 2 (right). Settings and Find My open over it full-window
/// with splits of their own, Settings' right pane being navigator 3. The phone layout keeps each split's navigators,
/// stacking the right pane over the left while it has a page.
class NavigatorService {
  NavigatorService() {
    ever(settingsPaneOpen, (bool open) {
      if (!open) activeSettingsPage.value = null;
    });
  }

  final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  /// Refreshed on every divider drag event, for readers that follow the left pane's width itself
  final Rxn listener = Rxn();

  /// Readers of [isAvatarOnly] watch this instead of [listener], so they rebuild only when the pane crosses
  /// [avatarOnlyWidth].
  final RxBool leftPaneNarrow = false.obs;

  /// In the phone layout the right pane covers the left only while this is true
  final RxBool chatPaneOpen = false.obs;
  late final PaneObserver chatPaneObserver = PaneObserver(chatPaneOpen);

  final RxBool settingsPaneOpen = false.obs;

  /// Dialogs and see-through popups, like a message's, don't count as covering
  final RouteObserver<ModalRoute> paneRouteObserver = _OpaqueRouteObserver();

  late final SectionObserver sectionObserver = SectionObserver(openSection);

  final Rxn<AppSection> openSection = Rxn<AppSection>();

  NavigatorState? get _root => key.currentState;
  NavigatorState? get _left => Get.keys[1]?.currentState;
  NavigatorState? get _right => Get.keys[2]?.currentState;
  NavigatorState? get _settings => Get.keys[3]?.currentState;

  /// Runtime type of the settings page open in the split view's right pane —
  /// settings list tiles highlight themselves when it matches their destination.
  final Rxn<Type> activeSettingsPage = Rxn<Type>();

  /// width of left side of split screen view
  double? _widthChatListLeft;

  /// width of right side of split screen view
  double? _widthChatListRight;

  /// width of settings right side split screen
  double? _widthSettings;

  set maxWidthLeft(double w) {
    _widthChatListLeft = w;
    if ((w < avatarOnlyWidth) != leftPaneNarrow.value) {
      // Set from a LayoutBuilder, where dirtying other widgets is not allowed
      WidgetsBinding.instance
          .addPostFrameCallback((_) => leftPaneNarrow.value = _widthChatListLeft! < avatarOnlyWidth);
    }
  }

  set maxWidthRight(double w) => _widthChatListRight = w;
  set maxWidthSettings(double w) => _widthSettings = w;

  /// Returns widthChatListLeft if in tablet mode, and 0 otherwise
  double widthChatListLeft(BuildContext context) => isTabletMode(context) ? _widthChatListLeft ?? 0 : 0;

  bool isTabletMode(BuildContext context) =>
      (!context.isPhone || context.width / context.height > 0.8) &&
      SettingsSvc.settings.tabletMode.value &&
      context.width > 600;

  /// Closes [route] without touching routes above it. Pops when [route] is on top, because only a pop reaches
  /// [routeObserver] subscribers' didPopNext; removeRoute does not.
  void closeRoute(Route route) {
    if (route.isCurrent) {
      route.navigator!.pop();
    } else if (route.isActive) {
      route.navigator!.removeRoute(route);
    }
  }
  bool get _tabletLayout {
    final context = _root?.context ?? Get.context;
    return context != null && isTabletMode(context);
  }

  /// Nothing is open over the chat list: no section, nothing pushed in either pane, nothing on the root navigator.
  /// Reads the panes themselves, since GetX's route tracking only sees the root navigator.
  bool get onChatList =>
      openSection.value == null &&
      !(_root?.canPop() ?? false) &&
      !(_left?.canPop() ?? false) &&
      !(_right?.canPop() ?? false);

  /// grab the available screen width, returning the split screen width if applicable
  /// this should *always* be used in place of context.width or similar
  double width(BuildContext context) {
    final key = Navigator.maybeOf(context)?.widget.key;
    if (key != null && key == Get.keys[1]) return _widthChatListLeft ?? context.width;
    if (key != null && key == Get.keys[2]) return _widthChatListRight ?? context.width;
    if (key != null && key == Get.keys[3]) return _widthSettings ?? context.width;
    return context.width;
  }

  double ratio(BuildContext context) => (_widthChatListLeft ?? context.width) / context.width;

  static const double avatarOnlyWidth = 300;

  bool isAvatarOnly(BuildContext context) =>
      (kIsDesktop || kIsWeb) && isTabletMode(context) && (_widthChatListLeft ?? context.width) < avatarOnlyWidth;

  static PageRoute _instantRoute(Widget widget) => PageRouteBuilder(
        pageBuilder: (_, _, _) => widget,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );

  /// Into Settings' right pane while Settings is on top, the chat list's otherwise
  Future<T?> push<T>(BuildContext context, Widget widget) {
    final pane = openSection.value == AppSection.settings ? _settings : _right;
    if (pane == null) {
      return Navigator.of(context).push<T>(ThemeSwitcher.buildPageRoute(
        builder: (BuildContext context) => TitleBarWrapper(child: widget),
      ));
    }
    return pane.push<T>(ThemeSwitcher.buildPageRoute(builder: (BuildContext context) => widget));
  }

  Future<void> pushLeft(BuildContext context, Widget widget) async {
    final left = _left;
    // The phone layout hides the left pane behind an open chat
    if (left != null && !_tabletLayout && chatPaneOpen.value) {
      await push(context, widget);
      return;
    }
    if (left == null) {
      await Navigator.of(context).push(ThemeSwitcher.buildPageRoute(
        builder: (BuildContext context) => TitleBarWrapper(child: widget),
      ));
      return;
    }
    await left.push(ThemeSwitcher.buildPageRoute(builder: (BuildContext context) => widget));
  }

  void _openSection(AppSection section, Widget page) {
    closeSections();
    _root?.push(ThemeSwitcher.buildPageRoute(settings: RouteSettings(name: section.name), builder: (_) => page));
  }

  /// Already in Settings, this just switches to [initialPage]
  void openSettings({Widget? initialPage}) {
    if (openSection.value == AppSection.settings) {
      if (initialPage != null) pushAndRemoveSettingsUntil(Get.context!, initialPage, (route) => route.isFirst);
      return;
    }
    _openSection(AppSection.settings, SettingsPage(initialPage: initialPage));
  }

  void openFindMy() {
    if (openSection.value == AppSection.findMy) return;
    _openSection(AppSection.findMy, const FindMyPage());
  }

  void closeSections() {
    final root = _root;
    if (root == null) return;
    for (final route in sectionObserver.routes.toList()) {
      root.removeRoute(route);
    }
  }

  Future<dynamic> pushSettings(BuildContext context, Widget widget, {Bindings? binding}) async {
    binding?.dependencies();
    return push(context, widget);
  }

  /// In the split view [predicate] picks what stays under [widget]; keep the placeholder with `route.isFirst`.
  /// The phone layout pushes over the current page, as a page opened from the list would be.
  void pushAndRemoveSettingsUntil(BuildContext context, Widget widget, bool Function(Route) predicate,
      {Bindings? binding}) {
    final settings = _settings;
    if (settings == null) {
      openSettings(initialPage: widget);
      return;
    }
    binding?.dependencies();
    if (_tabletLayout) {
      activeSettingsPage.value = widget.runtimeType;
      settings.pushAndRemoveUntil(_instantRoute(widget), predicate);
    } else {
      settings.push(ThemeSwitcher.buildPageRoute(builder: (BuildContext context) => widget));
    }
  }

  /// Closes Settings and Find My first, so what it opens is in view. The split view always swaps the chat pane
  /// instantly; elsewhere [animate] false skips the transition in.
  Future<void> pushAndRemoveUntil(BuildContext context, Widget widget, bool Function(Route) predicate,
      {bool closeActiveChat = true, bool animate = true}) async {
    final right = _right;
    if (right == null) {
      final page = TitleBarWrapper(child: widget);
      await Navigator.of(context).pushAndRemoveUntil(
          ThemeSwitcher.buildPageRoute(animateIn: animate, builder: (BuildContext context) => page), predicate);
      return;
    }
    closeSections();
    if (_tabletLayout) {
      if (closeActiveChat && ChatsSvc.activeChat != null) {
        Logger.debug("Closing active chat: ${ChatsSvc.activeChat!.chat.guid}", tag: "NavigatorService");
        cvc(ChatsSvc.activeChat!.chat).close();
      }
      await right.pushAndRemoveUntil(_instantRoute(widget), predicate);
    } else {
      await right.pushAndRemoveUntil(
          ThemeSwitcher.buildPageRoute(animateIn: animate, builder: (BuildContext context) => widget), predicate);
    }
  }

  /// Returns false when there was nothing to go back from
  bool back() {
    final root = _root;
    Route? top;
    root?.popUntil((route) {
      top = route;
      return true;
    });
    if (top != null && !top!.isFirst && SectionObserver._section(top) == null) {
      // Like a message's popup on the iOS skin
      root!.maybePop();
      return true;
    }
    switch (openSection.value) {
      case AppSection.settings:
        final settings = _settings;
        if (settings != null && settings.canPop()) {
          settings.maybePop();
        } else {
          // pop, not maybePop: Settings' PopScope sends back here, so maybePop would loop
          _root?.pop();
        }
        return true;
      case AppSection.findMy:
        _root?.maybePop();
        return true;
      case null:
        break;
    }
    final left = _left, right = _right;
    if (left == null || right == null) {
      Get.back();
      return true;
    }
    if (right.canPop()) {
      // maybePop, so an open chat closes its pickers before closing itself
      right.maybePop();
      return true;
    }
    if (left.canPop()) {
      left.maybePop();
      return true;
    }
    return false;
  }

  void backConversationView(BuildContext context) => back();

  void pop(BuildContext context, [Object? result]) => Navigator.of(context).pop(result);

  /// Remember to call `await ChatsSvc.setAllInactive()` after calling this function
  void closeAllConversationView(BuildContext context) => _right?.popUntil((route) => route.isFirst);
}

class _OpaqueRouteObserver extends RouteObserver<ModalRoute> {
  @override
  void didPush(Route route, Route? previousRoute) {
    if (route is! TransitionRoute || route.opaque) super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    if (route is! TransitionRoute || route.opaque) super.didPop(route, previousRoute);
  }
}

/// The first page of a split's right pane. It draws no transition: in the phone layout the left pane stands in for it
/// (see [PaneObserver.base]), and in the split view it's a placeholder that can stay still.
class PaneBasePage extends Page<void> {
  const PaneBasePage({required this.child}) : super(name: 'initial');

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => _PaneBaseRoute(this);
}

class _PaneBaseRoute extends PageRoute<void> with MaterialRouteTransitionMixin<void> {
  _PaneBaseRoute(PaneBasePage page) : super(settings: page);

  @override
  Widget buildContent(BuildContext context) => (settings as PaneBasePage).child;

  @override
  bool get maintainState => true;

  @override
  Widget buildTransitions(
          BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) =>
      child;
}

class PaneObserver extends NavigatorObserver {
  PaneObserver(this.open);

  final RxBool open;

  /// The pane's [PaneBasePage] route; the phone layout draws the left pane with its transitions
  final Rxn<PageRoute> base = Rxn<PageRoute>();

  /// The pages fully hide [base]. False again the moment the bottom page starts leaving or a back swipe moves it.
  final RxBool covered = false.obs;

  final List<Route> routes = [];

  Animation<double>? _bottom;

  /// For a navigator that went away without popping its pages, like a chat list Reset replaced
  void reset() {
    routes.clear();
    _update();
  }

  bool _tracked(Route? route) => route != null && route.settings is! Page;

  // Navigator callbacks run mid-transition, often during a build
  void _update() => WidgetsBinding.instance.addPostFrameCallback((_) {
        open.value = routes.isNotEmpty;
        _watchBottom();
      });

  void _watchBottom() {
    final bottom = routes.whereType<TransitionRoute>().where((route) => route.opaque).firstOrNull?.animation;
    if (bottom == _bottom) return;
    _bottom?.removeStatusListener(_onBottomStatus);
    _bottom = bottom?..addStatusListener(_onBottomStatus);
    _onBottomStatus(bottom?.status ?? AnimationStatus.dismissed);
  }

  void _onBottomStatus(AnimationStatus status) => covered.value = status.isCompleted;

  @override
  void didPush(Route route, Route? previousRoute) {
    if (route is PageRoute && route.settings is PaneBasePage) {
      WidgetsBinding.instance.addPostFrameCallback((_) => base.value = route);
    }
    if (_tracked(route)) routes.add(route);
    _update();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    routes.remove(route);
    _update();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    routes.remove(route);
    _update();
  }

  @override
  void didReplace({Route? newRoute, Route? oldRoute}) {
    final index = oldRoute == null ? -1 : routes.indexOf(oldRoute);
    if (index != -1) routes.removeAt(index);
    if (_tracked(newRoute)) routes.insert(index == -1 ? routes.length : index, newRoute!);
    _update();
  }
}

class SectionObserver extends NavigatorObserver {
  SectionObserver(this.open);

  final Rxn<AppSection> open;

  final List<Route> routes = [];

  static AppSection? _section(Route? route) =>
      AppSection.values.firstWhereOrNull((section) => section.name == route?.settings.name);

  // Updated right away, so a chat opened in the same frame sees the section gone
  void _update() => open.value = _section(routes.lastOrNull);

  @override
  void didPush(Route route, Route? previousRoute) {
    if (_section(route) != null) routes.add(route);
    _update();
  }

  @override
  void didPop(Route route, Route? previousRoute) {
    routes.remove(route);
    _update();
  }

  @override
  void didRemove(Route route, Route? previousRoute) {
    routes.remove(route);
    _update();
  }
}
