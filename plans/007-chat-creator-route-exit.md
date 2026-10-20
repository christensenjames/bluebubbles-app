# 007 — Give chats opened from the chat creator a real exit transition

- **Status**: DONE (code; on-device check needs a real send from the chat creator)
- **Commit**: e3cf75722
- **Severity**: MEDIUM
- **Category**: Missed opportunity (also Interruptibility)
- **Estimated scope**: 3 files, ~25 lines
- **Depends on**: 005, for the gesture preview; the button-back fade works without it

## Problem

When you start a chat from the new-chat screen, the app swaps the inline preview for the real
`ConversationView` with an instant route push. Instant is right here: the chat creator already
shows that chat's messages inline, so any visible transition would be a fake page change.
The route is a bare `PageRouteBuilder` with `transitionDuration: Duration.zero` and no
`reverseTransitionDuration`. Flutter defaults the reverse to the forward duration, so
**leaving** that chat is an instant cut. `PageRouteBuilder` also ignores the theme's
`PageTransitionsTheme`, so it can never show the predictive back card, even after plan 005.
A chat reached from the chat list peeks; the same chat reached from the creator pops with a
hard cut.

There are three call sites with the same shape:

```dart
// lib/app/layouts/chat_creator/chat_creator.dart:528-548 — current (existing chat picked)
                              NavigationSvc.pushAndRemoveUntil(
                                Get.context!,
                                ConversationView(
                                  chat: existingChat,
                                  customService: messagesService,
                                  fromChatCreator: true,
                                ),
                                (route) => route.isFirst,
                                // don't force close the active chat in tablet mode
                                closeActiveChat: false,
                                // only used in non-tablet mode context
                                customRoute: PageRouteBuilder(
                                  pageBuilder: (_, _, _) => TitleBarWrapper(
                                      child: ConversationView(
                                    chat: existingChat,
                                    customService: messagesService,
                                    fromChatCreator: true,
                                  )),
                                  transitionDuration: Duration.zero,
                                ),
                              );
```

```dart
// lib/app/layouts/chat_creator/chat_creator.dart:622-635 — current (new chat created)
                                NavigationSvc.pushAndRemoveUntil(
                                  Get.context!,
                                  ConversationView(chat: newChat),
                                  (route) => route.isFirst,
                                  customRoute: PageRouteBuilder(
                                    pageBuilder: (_, _, _) => TitleBarWrapper(
                                      child: ConversationView(
                                        chat: newChat,
                                        fromChatCreator: true,
                                      ),
                                    ),
                                    transitionDuration: Duration.zero,
                                  ),
                                );
```

```dart
// lib/app/layouts/chat_creator/chat_creator_controller.dart:689-704 — current (send from creator)
    NavigationSvc.pushAndRemoveUntil(
      Get.context!,
      ConversationView(chat: chat, customService: messagesService, fromChatCreator: true),
      (route) => route.isFirst,
      closeActiveChat: false,
      customRoute: PageRouteBuilder(
        pageBuilder: (_, __, ___) => TitleBarWrapper(
          child: ConversationView(
            chat: chat,
            customService: messagesService,
            fromChatCreator: true,
          ),
        ),
        transitionDuration: Duration.zero,
      ),
    );
```

`customRoute` is only used in phone layout (`lib/services/ui/navigator/navigator_service.dart:128-134`).
Tablet layout uses a GetX route and is unaffected.

## Target

Push stays instant. Pop uses the skin's normal page route, so on Material and Samsung it gets
the predictive card during a back gesture and Flutter's default fade-forwards on a button
back. On iOS skin it gets the same `CustomCupertinoPageTransition` slide as every other page.

Note: after this plan shipped, `main.dart` set Android to `SystemBackPageTransitionsBuilder`,
so a button back now moves the page 96dp right as it fades, like the system Settings app.

Add an `instantPush` flag to the existing route factory:

```dart
// target — lib/app/wrappers/theme_switcher.dart
  static PageRoute<T> buildPageRoute<T>(
      {required Widget Function(BuildContext context) builder, bool instantPush = false}) {
    switch (SettingsSvc.settings.skin.value) {
      case Skins.iOS:
        return PageRouteBuilder<T>(
            transitionDuration: instantPush ? Duration.zero : const Duration(milliseconds: 300),
            reverseTransitionDuration: const Duration(milliseconds: 300),
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
```

```dart
// target — same file, top level, below the ThemeSwitcher class
class _InstantPushMaterialPageRoute<T> extends MaterialPageRoute<T> {
  _InstantPushMaterialPageRoute({required super.builder});

  @override
  Duration get transitionDuration => Duration.zero;
}
```

Values and why:

- **iOS 300ms both ways** is `PageRouteBuilder`'s own default, which today's iOS branch
  inherits implicitly. Writing it out keeps the non-instant path identical.
- **Material/Samsung reverse duration is not set.** `MaterialRouteTransitionMixin` takes it
  from the theme's builder (`~/sdk/flutter/packages/flutter/lib/src/material/page.dart:96-98`),
  so the exit matches every other Material page exactly. Do not hardcode a number.
- **Merging the `Material` and `Samsung` cases** is fine because both returned the identical
  `MaterialPageRoute<T>(builder: builder)`.

Each of the three call sites then becomes:

```dart
// target — chat_creator.dart:539-547 (the other two sites follow the same shape)
                                customRoute: ThemeSwitcher.buildPageRoute(
                                  instantPush: true,
                                  builder: (_) => TitleBarWrapper(
                                      child: ConversationView(
                                    chat: existingChat,
                                    customService: messagesService,
                                    fromChatCreator: true,
                                  )),
                                ),
```

## Repo conventions to follow

- `ThemeSwitcher.buildPageRoute` is the single per-skin route factory. 27 call sites use it,
  e.g. `navigator_service.dart:82-84`. Extend it; don't add a parallel helper elsewhere.
- Keep the `TitleBarWrapper(child: ConversationView(...))` content exactly as it is at each
  site.
- `chat_creator.dart` and `chat_creator_controller.dart` may need
  `import 'package:bluebubbles/app/wrappers/theme_switcher.dart';`. Add it only if the analyzer
  says the symbol is undefined.

## Steps

1. `lib/app/wrappers/theme_switcher.dart`: change `buildPageRoute` to the **Target** form and
   add `_InstantPushMaterialPageRoute` below the `ThemeSwitcher` class.
2. `lib/app/layouts/chat_creator/chat_creator.dart:539-547`: replace the `PageRouteBuilder`
   with `ThemeSwitcher.buildPageRoute(instantPush: true, builder: (_) => …)`, carrying over the
   same `TitleBarWrapper` subtree.
3. `lib/app/layouts/chat_creator/chat_creator.dart:626-634`: same replacement.
4. `lib/app/layouts/chat_creator/chat_creator_controller.dart:694-703`: same replacement.
5. Run `grep -rn "transitionDuration: Duration.zero" lib/app/layouts/chat_creator`. It must
   print nothing.

## Boundaries

- Do NOT make the push animate. The instant swap from the inline preview is deliberate.
- Do NOT touch `buildTransparentPageRoute` or any other `PageRouteBuilder` in the repo.
- Do NOT touch `NavigationService.pushAndRemoveUntil` or the tablet `GetPageRoute` path.
- Do NOT change the `activeController.value = null` / focus handling before the push in
  `chat_creator_controller.dart:681-687`. It prevents a GlobalKey clash.
- If code at the cited lines differs from the excerpts (drift since `e3cf75722`), STOP and
  report.

## Verification

- **Mechanical**:
  - `export PATH="/home/james/sdk/flutter/bin:$PATH" && flutter analyze --no-pub --no-fatal-infos`.
    The result must have 0 errors, 0 warnings, and no new infos in the three touched files
    (compare per file against `e3cf75722`).
  - `flutter build linux --debug --no-pub` must compile.
  - Pixel: `flutter build apk --release --flavor prod -Porg.gradle.workers.max=2
    -Pkotlin.daemon.jvm.options=-Xmx1536m`, then `(cd android && ./gradlew --stop)`; install
    only if the output contains `✓ Built`.
- **Feel check** on the Pixel, Material skin:
  - Chat list → new-chat button → pick an existing contact. The chat appears with no visible
    transition and no flash, exactly as before.
  - In that chat, tap the header back arrow. The chat now leaves with the same fade as a chat
    opened from the list, not a hard cut.
  - Note: a button back now uses `SystemBackPageTransitionsBuilder`'s close motion instead.
  - Open it the same way again and drag slowly from the left edge. With 005 applied, the
    chat shrinks into the predictive card over the chat list. Release mid-way and it
    completes; drag back and it cancels.
  - Send a first message from the creator (third call site). The chat appears instantly, and
    back from it animates.
  - Switch to the iOS skin and repeat the first two checks. The push is instant, and back
    slides the chat out to the right as on other pages.
- **Done when**: no route opened from the chat creator exits with a cut, and its entry is
  still instant.
