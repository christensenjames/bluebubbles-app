import 'dart:async';
import 'dart:isolate';
import 'dart:math';
import 'dart:ui';

import 'package:adaptive_theme/adaptive_theme.dart';
import 'package:async_task/async_task_extension.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:bluebubbles/app/wrappers/bb_scaffold.dart';
import 'package:bluebubbles/app/components/custom/custom_error_box.dart';
import 'package:bluebubbles/app/components/custom/system_back_page_transitions_builder.dart';
import 'package:bluebubbles/helpers/backend/startup_tasks.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/network/http_overrides.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/utils/media_kit_hot_restart_fix.dart'
    if (dart.library.html) 'package:bluebubbles/utils/media_kit_hot_restart_fix_web.dart';
import 'package:bluebubbles/utils/window_effects.dart';
import 'package:bluebubbles/app/layouts/conversation_list/pages/conversation_list.dart';
import 'package:bluebubbles/app/layouts/startup/failure_to_start.dart';
import 'package:bluebubbles/app/layouts/setup/setup_view.dart';
import 'package:bluebubbles/app/layouts/startup/splash_screen.dart';
import 'package:bluebubbles/app/wrappers/titlebar_wrapper.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:easy_debounce/easy_debounce.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' hide Priority;
import 'package:flutter/services.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:get/get.dart';
import 'package:get_it/get_it.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:secure_application/secure_application.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:tray_manager/tray_manager.dart';
import 'package:universal_html/html.dart' as html;
import 'package:universal_io/io.dart';
import 'package:window_manager/window_manager.dart';
import 'package:windows_taskbar/windows_taskbar.dart';

bool isAuthing = false;

@pragma('vm:entry-point')
//ignore: prefer_void_to_null
Future<Null> main(List<String> arguments) async {
  await initApp(false, arguments);
}

@pragma('vm:entry-point')
// ignore: prefer_void_to_null
Future<Null> bubble() async {
  await initApp(true, []);
}

//ignore: prefer_void_to_null
Future<Null> initApp(bool bubble, List<String> arguments) async {
  // Startup failures can reach the error handlers before BaseLogger is registered.
  bool loggerReady() => GetIt.I.isRegistered<BaseLogger>() && GetIt.I.isReadySync<BaseLogger>();

  runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    /* ----- DESKTOP NATIVE SPLASH STATUS ----- */
    // Pushes startup status to the native splash; detached once it's dismissed.
    void Function()? detachSplashStatus;
    Future<void> dismissSplash() async {
      try {
        await const MethodChannel('bluebubbles/splash').invokeMethod('closeSplash');
      } catch (_) {}
      detachSplashStatus?.call();
    }

    if (kIsDesktop && !bubble && arguments.firstOrNull != "minimized") {
      const splashChannel = MethodChannel('bluebubbles/splash');
      bool titleBarApplied = false;
      void pushStatus() {
        splashChannel.invokeMethod('setStatus', StartupTasks.status.value).catchError((_) => null);

        // Keyed on the service being ready rather than on a status string, so
        // adding or renaming startup steps can't make this fire too early.
        if (Platform.isLinux && !titleBarApplied && GetIt.I.isRegistered<SettingsService>()) {
          titleBarApplied = true;
          unawaited(() async {
            await windowManager.ensureInitialized();
            await windowManager.setTitleBarStyle(SettingsSvc.settings.titleBarStyle.value == BBTitleBarStyle.native
                ? TitleBarStyle.normal
                : TitleBarStyle.hidden);
          }());
        }
      }

      void pushProgress() {
        splashChannel.invokeMethod('setProgress', StartupTasks.progress.value).catchError((_) => null);
      }

      StartupTasks.status.addListener(pushStatus);
      StartupTasks.progress.addListener(pushProgress);
      pushStatus();
      detachSplashStatus = () {
        StartupTasks.status.removeListener(pushStatus);
        StartupTasks.progress.removeListener(pushProgress);
      };
    }

    /* ----- RANDOM STUFF INITIALIZATION ----- */
    HttpOverrides.global = CustomHttpContext();
    dynamic exception;
    StackTrace? stacktrace;

    FlutterError.onError = (details) {
      if (loggerReady()) {
        Logger.error("Rendering Error: ${details.exceptionAsString()}", error: details.exception, trace: details.stack);
      } else {
        FlutterError.presentError(details);
      }
    };

    try {
      await StartupTasks.initStartupServices(isBubble: bubble);

      // Once all the services are initialized, we need to perform some
      // startup tasks to ensure that the app has the information it needs.
      StartupTasks.onStartup().then((_) {
        Logger.info("Startup tasks completed");
      }).catchError((e, s) {
        Logger.error("Failed to complete startup tasks!", error: e, trace: s);
      });

      /* ----- DATE FORMATTING INITIALIZATION ----- */
      await initializeDateFormatting();
      setDefaultDateLocale();

      /* ----- MEDIAKIT INITIALIZATION ----- */
      clearLeakedMpvWakeupCallbacks(); // must run first — see media_kit_hot_restart_fix.dart
      MediaKit.ensureInitialized();

      /* ----- SPLASH SCREEN INITIALIZATION ----- */
      if (!SettingsSvc.settings.finishedSetup.value && !kIsWeb && !kIsDesktop) {
        runApp(MaterialApp(
            home: const SplashScreen(shouldNavigate: false),
            theme: ThemeData(
              colorScheme: ColorScheme.fromSwatch(
                  backgroundColor:
                      PlatformDispatcher.instance.platformBrightness == Brightness.dark ? Colors.black : Colors.white),
            )));
      }

      /* ----- TIME ZONE INITIALIZATION ----- */
      if (!kIsWeb) {
        tz.initializeTimeZones();
        try {
          tz.setLocalLocation(tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier));
        } catch (_) {}
      }

      /* ----- ANDROID SPECIFIC INITIALIZATION ----- */
      if (!kIsWeb && !kIsDesktop) {
        /* ----- MLKIT INITIALIZATION ----- */
        // Defer MLKit model check - not critical for startup
        Future.microtask(() async {
          if (!await EntityExtractorModelManager().isModelDownloaded(EntityExtractorLanguage.english.name)) {
            EntityExtractorModelManager().downloadModel(EntityExtractorLanguage.english.name, isWifiRequired: false);
          }
        });
      }

      /* ----- DESKTOP SPECIFIC INITIALIZATION ----- */
      if (kIsDesktop) {
        /* ----- WINDOW INITIALIZATION ----- */
        await windowManager.ensureInitialized();
        await windowManager.setPreventClose(SettingsSvc.settings.closeToTrayEffective);
        await windowManager.setTitle('BlueBubbles');
        await Window.initialize();
        if (Platform.isWindows) {
          await Window.hideWindowControls();
        } else if (Platform.isLinux) {
          await windowManager.setTitleBarStyle(SettingsSvc.settings.titleBarStyle.value == BBTitleBarStyle.native
              ? TitleBarStyle.normal
              : TitleBarStyle.hidden);
        }
        windowManager.addListener(DesktopWindowListener.instance);
        doWhenWindowReady(() async {
          await windowManager.setMinimumSize(const Size(300, 300));
          Display primary = await ScreenRetriever.instance.getPrimaryDisplay();

          double width = PrefsSvc.desktop.getWindowWidth() ?? 1280;
          double height = PrefsSvc.desktop.getWindowHeight() ?? 720;

          width = width.clamp(300, max(300, primary.size.width));
          height = height.clamp(300, max(300, primary.size.height));

          if (isWaylandSession) {
            // Wayland forbids a client from positioning itself, so only restore
            // the size and leave placement to the compositor.
            await windowManager.setSize(Size(width, height));
          } else {
            // Restore position otherwise
            final centered = await calcWindowPosition(Size(width, height), Alignment.center);
            double posX = PrefsSvc.desktop.getWindowX() ?? centered.dx;
            double posY = PrefsSvc.desktop.getWindowY() ?? centered.dy;
            Rect visibleArea(Display d) => (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size);
            // setBounds scales by the primary's DPI, so a display at another scale would land off-screen.
            final center = Rect.fromLTWH(posX, posY, width, height).center;
            final area = (await ScreenRetriever.instance.getAllDisplays())
                    .where((d) => d.scaleFactor == primary.scaleFactor)
                    .map(visibleArea)
                    .firstWhereOrNull((a) => a.contains(center)) ??
                visibleArea(primary);
            posX = posX.clamp(area.left, max(area.left, area.right - width));
            posY = posY.clamp(area.top, max(area.top, area.bottom - height));
            await windowManager.setBounds(Rect.fromLTWH(posX, posY, width, height));
            await PrefsSvc.desktop.setWindowOffsets(x: posX, y: posY);
          }
          await PrefsSvc.desktop.setWindowDimensions(width: width, height: height);

          await windowManager.setTitle('BlueBubbles');
          if (arguments.firstOrNull != "minimized" || !SettingsSvc.settings.showTrayIcon.value) {
            await windowManager.show();
          } else {
            await windowManager.hide();
          }
          await dismissSplash();
          unawaited(ThemeSvc.initDynamicColorsDeferred()); // Linux: deferred past splash
          bool shouldAuthenticate =
              !Platform.isLinux && SettingsSvc.canAuthenticate && SettingsSvc.settings.shouldSecure.value;
          if (!shouldAuthenticate) {
            ChatsSvc.init();
            SocketSvc.init();
          }
        });

        await dotenv.load();
      }

      /* ----- EMOJI FONT INITIALIZATION ----- */
      Future.microtask(() => FilesystemSvc.checkFont());
    } catch (e, s) {
      exception = e;
      stacktrace = s;
    }

    if (exception == null) {
      /* ----- THEME INITIALIZATION ----- */
      final pair = ThemeSvc.renderThemes(ThemeStruct.getLightTheme(), ThemeStruct.getDarkTheme());
      ThemeData light = pair.light;
      ThemeData dark = pair.dark;

      runApp(MaterialApp(
          home: Main(
        lightTheme: light,
        darkTheme: dark,
        savedThemeMode: await AdaptiveTheme.getThemeMode(),
      )));
    } else {
      runApp(FailureToStart(e: exception, s: stacktrace));
      if (kIsDesktop) {
        // Windows (BDW_HIDE_ON_STARTUP) ignores show() until bitsdojo's window-ready callback has fired.
        doWhenWindowReady(() async {
          await windowManager.ensureInitialized();
          await windowManager.show();
          await dismissSplash();
        });
      }
      throw Exception("$exception $stacktrace");
    }
  }, (dynamic error, StackTrace stackTrace) {
    print("Failure during app initialization: $error");
    print(stackTrace);
    if (loggerReady()) {
      Logger.error("Unhandled Exception", trace: stackTrace, error: error);
    }
  });
}

bool get isWaylandSession =>
    Platform.isLinux &&
    (Platform.environment['XDG_SESSION_TYPE'] == 'wayland' || Platform.environment.containsKey('WAYLAND_DISPLAY'));

class DesktopWindowListener extends WindowListener {
  DesktopWindowListener._();

  static final DesktopWindowListener instance = DesktopWindowListener._();

  @override
  void onWindowFocus() {
    LifecycleSvc.open();
  }

  @override
  void onWindowBlur() {
    LifecycleSvc.close();
  }

  @override
  void onWindowResized() async {
    Size size = await windowManager.getSize();
    await PrefsSvc.desktop.setWindowDimensions(width: size.width, height: size.height);
  }

  @override
  void onWindowMoved() async {
    Offset offset = await windowManager.getPosition();
    await PrefsSvc.desktop.setWindowOffsets(x: offset.dx, y: offset.dy);
  }

  @override
  void onWindowEvent(String eventName) async {
    switch (eventName) {
      case "hide":
        await setSystemTrayContextMenu(windowHidden: true);
        break;
      case "show":
        await setSystemTrayContextMenu(windowHidden: false);
        break;
    }
  }

  @override
  void onWindowClose() async {
    if (await windowManager.isPreventClose()) {
      await windowManager.hide();
    } else if (Platform.isLinux) {
      exit(0);
    }
  }
}

class Main extends StatelessWidget {
  final ThemeData darkTheme;
  final ThemeData lightTheme;
  final AdaptiveThemeMode? savedThemeMode;

  const Main({super.key, required this.lightTheme, required this.darkTheme, this.savedThemeMode});

  static const _pageTransitionsTheme = PageTransitionsTheme(builders: {
    TargetPlatform.android: SystemBackPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.windows: ZoomPageTransitionsBuilder(),
    TargetPlatform.linux: ZoomPageTransitionsBuilder(),
  });

  @override
  Widget build(BuildContext context) {
    return AdaptiveTheme(
      light: lightTheme.copyWith(
          textSelectionTheme: TextSelectionThemeData(selectionColor: lightTheme.colorScheme.primary)),
      dark:
          darkTheme.copyWith(textSelectionTheme: TextSelectionThemeData(selectionColor: darkTheme.colorScheme.primary)),
      initial: savedThemeMode ?? AdaptiveThemeMode.system,
      builder: (theme, darkTheme) => GetMaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'BlueBubbles',
        theme: theme.copyWith(
          appBarTheme: theme.appBarTheme.copyWith(elevation: 0.0),
          pageTransitionsTheme: _pageTransitionsTheme,
          dialogTheme: DialogThemeData(
            barrierColor: theme.colorScheme.shadow.withValues(alpha: 0.6),
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
        darkTheme: darkTheme.copyWith(
          appBarTheme: darkTheme.appBarTheme.copyWith(elevation: 0.0),
          pageTransitionsTheme: _pageTransitionsTheme,
          dialogTheme: DialogThemeData(
            barrierColor: darkTheme.colorScheme.shadow.withValues(alpha: 0.6),
            backgroundColor: darkTheme.colorScheme.surfaceContainerHighest,
          ),
        ),
        navigatorKey: NavigationSvc.key,
        navigatorObservers: [routeObserver],
        scrollBehavior: const MaterialScrollBehavior().copyWith(
          // Specifically for GNU/Linux & Android-x86 family, where touch isn't interpreted as a drag device by Flutter apparently.
          dragDevices: Platform.isLinux || Platform.isAndroid ? PointerDeviceKind.values.toSet() : null,
          // Prevent scrolling with multiple fingers accelerating the scrolling
          multitouchDragStrategy: MultitouchDragStrategy.latestPointer,
        ),
        home: const Home(),
        shortcuts: {
          _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.comma): const OpenSettingsIntent(),
          _NoLockKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.keyN): const OpenNewChatCreatorIntent(),
          if (kIsDesktop)
            _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyN): const OpenNewChatCreatorIntent(),
          _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyF): const OpenSearchIntent(),
          _NoLockKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.keyR): const ReplyRecentIntent(),
          if (kIsDesktop) _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyR): const ReplyRecentIntent(),
          _NoLockKeySet(LogicalKeyboardKey.alt, LogicalKeyboardKey.keyG): const StartIncrementalSyncIntent(),
          if (kIsDesktop)
            _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.keyR):
                const StartIncrementalSyncIntent(),
          if (kIsDesktop)
            _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyG): const StartIncrementalSyncIntent(),
          _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.exclamation):
              const HeartRecentIntent(),
          _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.at):
              const LikeRecentIntent(),
          _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.numberSign):
              const DislikeRecentIntent(),
          _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.dollar):
              const LaughRecentIntent(),
          _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.percent):
              const EmphasizeRecentIntent(),
          _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.caret):
              const QuestionRecentIntent(),
          _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.arrowDown): const OpenNextChatIntent(),
          if (kIsDesktop) _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.tab): const OpenNextChatIntent(),
          _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.arrowUp): const OpenPreviousChatIntent(),
          if (kIsDesktop)
            _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift, LogicalKeyboardKey.tab):
                const OpenPreviousChatIntent(),
          _NoLockKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyI): const OpenChatDetailsIntent(),
          _NoLockKeySet.noRepeat(LogicalKeyboardKey.escape): const GoBackIntent(),
        },
        builder: (context, child) => SafeArea(
          top: false,
          bottom: false,
          // secure_application has no Linux implementation; mounting it (and the
          // SecureGate below) throws MissingPluginException on every lifecycle
          // event, which breaks window close/hide once the app is past setup.
          // Bypass the secure wrapper entirely on Linux.
          child: Platform.isLinux
              ? TitleBarWrapper(child: _withGoBack(context, child))
              : SecureApplication(
                  child: Builder(
                    builder: (context) {
                      if (SettingsSvc.canAuthenticate && (!LifecycleSvc.isAlive || !StartupTasks.uiReady.isCompleted)) {
                        if (SettingsSvc.settings.shouldSecure.value) {
                          SecureApplicationProvider.of(context, listen: false)!.lock();
                          if (SettingsSvc.settings.securityLevel.value == SecurityLevel.locked_and_secured) {
                            SecureApplicationProvider.of(context, listen: false)!.secure();
                          }
                        }
                      }
                      return TitleBarWrapper(
                        child: SecureGate(
                          blurr: 5,
                          opacity: 0,
                          lockedBuilder: (context, controller) {
                            final localAuth = LocalAuthentication();
                            if (!isAuthing) {
                              isAuthing = true;
                              localAuth
                                  .authenticate(
                                localizedReason: 'Please authenticate to unlock BlueBubbles',
                                persistAcrossBackgrounding: true,
                              )
                                  .then((result) {
                                isAuthing = false;
                                if (result) {
                                  if (!context.mounted) return;
                                  SecureApplicationProvider.of(context, listen: false)!.authSuccess(unlock: true);
                                  if (kIsDesktop) {
                                    Future.delayed(Duration.zero, () {
                                      ChatsSvc.init();
                                      SocketSvc.init();
                                    });
                                  }
                                }
                              });
                            }
                            return Container(
                              color: context.theme.colorScheme.surface,
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: <Widget>[
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 20.0),
                                      child: Text(
                                        "BlueBubbles is currently locked. Please unlock to access your messages.",
                                        style: context.theme.textTheme.titleLarge,
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    Container(height: 20.0),
                                    ClipOval(
                                      child: Material(
                                        color: context.theme.colorScheme.primary, // button color
                                        child: InkWell(
                                          child: SizedBox(
                                              width: 60,
                                              height: 60,
                                              child: Icon(Icons.lock_open, color: context.theme.colorScheme.onPrimary)),
                                          onTap: () async {
                                            final localAuth = LocalAuthentication();
                                            bool didAuthenticate = await localAuth.authenticate(
                                              localizedReason: 'Please authenticate to unlock BlueBubbles',
                                              persistAcrossBackgrounding: true,
                                            );
                                            if (didAuthenticate) {
                                              controller!.authSuccess(unlock: true);
                                              if (kIsDesktop) {
                                                Future.delayed(Duration.zero, () {
                                                  ChatsSvc.init();
                                                  SocketSvc.init();
                                                });
                                              }
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          child: _withGoBack(context, child),
                        ),
                      );
                    },
                  ),
                ),
        ),
        defaultTransition: Transition.cupertino,
      ),
    );
  }
}

// Above the navigator so pages pushed on the root navigator (phone layout) inherit Escape-to-go-back.
Widget _withGoBack(BuildContext context, Widget? child) =>
    Actions(actions: {GoBackIntent: GoBackAction(context)}, child: child ?? Container());

// The GTK embedder reports a lock mode that was already on as a held lock key, which LogicalKeySet counts as extra.
class _NoLockKeySet extends LogicalKeySet {
  _NoLockKeySet(super.key1, [super.key2, super.key3]) : includeRepeats = true;

  // Repeats of a held Escape would otherwise slip past the composer's KeyDown-only handlers and close the chat.
  _NoLockKeySet.noRepeat(super.key1) : includeRepeats = false;

  final bool includeRepeats;

  static final Set<LogicalKeyboardKey> _lockKeys = {
    LogicalKeyboardKey.capsLock,
    LogicalKeyboardKey.numLock,
    LogicalKeyboardKey.scrollLock,
  };

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (event is! KeyDownEvent && !(includeRepeats && event is KeyRepeatEvent)) return false;
    final pressed = state.logicalKeysPressed.difference(_lockKeys);
    return triggers.contains(event.logicalKey) &&
        setEquals(LogicalKeyboardKey.collapseSynonyms(keys), LogicalKeyboardKey.collapseSynonyms(pressed));
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with WidgetsBindingObserver, TrayListener {
  final ReceivePort port = ReceivePort();
  bool serverCompatible = true;
  bool fullyLoaded = false;
  Worker? _trayWorker;

  @override
  void initState() {
    super.initState();

    // Bind the lifecycle events
    WidgetsBinding.instance.addObserver(this);

    /* ----- APP REFRESH LISTENER INITIALIZATION ----- */
    EventDispatcherSvc.stream.listen((event) {
      if (event.type == 'refresh-all') {
        setState(() {});
      } else if (event.type == 'settings-replaced' && _trayWorker != null) {
        _bindTrayWorker();
        _applyTrayState();
      }
    });

    SchedulerBinding.instance.addPostFrameCallback((_) async {
      StartupTasks.uiReady.complete();

      if (!LifecycleSvc.isBubble && !kIsWeb && !kIsDesktop) {
        LifecycleSvc.createFakePort();
      }

      ErrorWidget.builder = (FlutterErrorDetails error) {
        Logger.error("An unexpected error occurred when rendering.", error: error.exception, trace: error.stack);
        return CustomErrorWidget(
          "An unexpected error occurred when rendering.",
        );
      };
      /* ----- SERVER VERSION CHECK ----- */
      if (kIsWeb && SettingsSvc.settings.finishedSetup.value) {
        final serverDetails = SettingsSvc.getServerDetails();
        if (!serverDetails.minimumWebSupportedVersion) {
          setState(() {
            serverCompatible = false;
          });
        }

        /* ----- CTRL-F OVERRIDE ----- */
        html.document.onKeyDown.listen((e) {
          if (e.keyCode == 114 || (e.ctrlKey && e.keyCode == 70)) {
            e.preventDefault();
          }
        });
      }

      if (kIsDesktop) {
        if (Platform.isWindows) {
          /* ----- CONTACT IMAGE CACHE DELETION ----- */
          Directory temp = FilesystemSvc.appTemp;
          if (await temp.exists()) await temp.delete(recursive: true);

          /* ----- BADGE ICON LISTENER ----- */
          Future<void> updateBadge(int count) async {
            try {
              if (count == 0 || !SettingsSvc.settings.windowsTaskbarBadge.value) {
                await WindowsTaskbar.resetOverlayIcon();
              } else if (count <= 9) {
                await WindowsTaskbar.setOverlayIcon(ThumbnailToolbarAssetIcon('assets/badges/badge-$count.ico'));
              } else {
                await WindowsTaskbar.setOverlayIcon(ThumbnailToolbarAssetIcon('assets/badges/badge-10.ico'));
              }
            } catch (_) {}
          }

          unawaited(updateBadge(ChatsSvc.unreadCount.value));
          ChatsSvc.unreadCount.listen(updateBadge);

          /* ----- WINDOW EFFECT INITIALIZATION ----- */
          EventDispatcherSvc.stream.listen((event) async {
            if (event.type == 'theme-update') {
              EasyDebounce.debounce('window-effect', const Duration(milliseconds: 500), () async {
                if (mounted) {
                  await WindowEffects.setEffect(color: context.theme.colorScheme.surface);
                }
              });
            }
          });

          Future(() => EventDispatcherSvc.emit("theme-update", null));
        }

        /* ----- SYSTEM TRAY INITIALIZATION ----- */
        if (SettingsSvc.settings.showTrayIcon.value) await initSystemTray();
        trayManager.addListener(this);
        _bindTrayWorker();
      }

      if (!SettingsSvc.settings.finishedSetup.value) {
        setState(() {
          fullyLoaded = true;
        });
      } else {
        if ((FilesystemSvc.androidInfo?.version.sdkInt ?? 0) >= 33) {
          Permission.notification.request();
        }
      }
    });
  }

  void _bindTrayWorker() {
    _trayWorker?.dispose();
    _trayWorker = ever(SettingsSvc.settings.showTrayIcon, (bool _) => _applyTrayState());
  }

  Future<void> _applyTrayState() async {
    await windowManager.setPreventClose(SettingsSvc.settings.closeToTrayEffective);
    if (SettingsSvc.settings.showTrayIcon.value) {
      await initSystemTray();
    } else {
      await trayManager.destroy();
    }
  }

  @override
  void onTrayIconMouseDown() async {
    await showAndFocusWindow();
  }

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'show_app':
        await showAndFocusWindow();
        break;
      case 'hide_app':
        await windowManager.hide();
        break;
      case 'close_app':
        if (Platform.isLinux) exit(0);
        await windowManager.setPreventClose(false);
        await windowManager.close();
        break;
    }
  }

  @override
  void dispose() {
    // Clean up observer when app is fully closed
    WidgetsBinding.instance.removeObserver(this);
    _trayWorker?.dispose();
    windowManager.removeListener(DesktopWindowListener.instance);
    if (kIsDesktop) {
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  /// Just in case the theme doesn't change automatically
  /// Workaround for adaptive_theme issue #32
  @override
  void didChangePlatformBrightness() {
    super.didChangePlatformBrightness();
    if (AdaptiveTheme.maybeOf(context)?.mode == AdaptiveThemeMode.system) {
      if (AdaptiveTheme.maybeOf(context)?.brightness == Brightness.light) {
        AdaptiveTheme.maybeOf(context)?.setLight();
      } else {
        AdaptiveTheme.maybeOf(context)?.setDark();
      }
      AdaptiveTheme.maybeOf(context)?.setSystem();

      EventDispatcherSvc.emit("theme-update", null);
    }
  }

  /// Render
  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: {
        OpenSettingsIntent: OpenSettingsAction(context),
        OpenNewChatCreatorIntent: OpenNewChatCreatorAction(context),
        OpenSearchIntent: OpenSearchAction(context),
        OpenNextChatIntent: OpenNextChatAction(context),
        OpenPreviousChatIntent: OpenPreviousChatAction(context),
        StartIncrementalSyncIntent: StartIncrementalSyncAction(),
      },
      child: Obx(() => BBScaffold(
            backgroundColor: context.theme.colorScheme.surface.themeOpacity(context),
            body: Builder(
              builder: (BuildContext context) {
                if (SettingsSvc.settings.finishedSetup.value) {
                  if (!serverCompatible && kIsWeb) {
                    return const FailureToStart(
                      otherTitle: "Server version too low, please upgrade!",
                      e: "Required Server Version: v0.2.0",
                    );
                  }
                  return ConversationList(
                    showArchivedChats: false,
                    showUnknownSenders: false,
                  );
                } else {
                  return PopScope(
                    canPop: false,
                    child: TitleBarWrapper(
                        child: kIsWeb || kIsDesktop ? const SetupView() : SplashScreen(shouldNavigate: fullyLoaded)),
                  );
                }
              },
            ),
          )),
    );
  }
}

Future<void> initSystemTray() async {
  String path;
  if (Platform.isWindows) {
    path = 'assets/icon/icon.ico';
  } else if (isFlatpak) {
    path = 'app.bluebubbles.BlueBubbles';
  } else if (isSnap) {
    path = p.joinAll([p.dirname(Platform.resolvedExecutable), 'data/flutter_assets/assets/icon', 'icon.png']);
  } else {
    path = 'assets/icon/icon.png';
  }

  await trayManager.setIcon(path);
  if (Platform.isWindows) await trayManager.setToolTip("BlueBubbles");
  await setSystemTrayContextMenu(windowHidden: !appWindow.isVisible);
}

Future<void> setSystemTrayContextMenu({bool windowHidden = false}) async {
  if (!SettingsSvc.settings.showTrayIcon.value) return;
  await trayManager.setContextMenu(Menu(
    items: [
      MenuItem(label: windowHidden ? 'Show App' : 'Hide App', key: windowHidden ? 'show_app' : 'hide_app'),
      MenuItem.separator(),
      MenuItem(label: 'Close App', key: 'close_app'),
    ],
  ));
}
