# 005 — Let the conversation screen follow the predictive back gesture

- **Status**: DONE
- **Commit**: e3cf75722
- **Severity**: HIGH
- **Category**: Interruptibility
- **Estimated scope**: 1 file, ~20 lines

## Problem

Leaving a chat is the most frequent back action in the app, and it is the one place where
Android's back gesture does nothing until release. Swiping from the screen edge inside a chat shows only the
system's arrow chip. The page does not shrink or move, and the chat list does not appear behind
it. On release the page plays a canned fade that has nothing to do with the finger. Every
other Material page (Settings, Settings sub-pages, Chat details) already shrinks into a
rounded card that tracks the finger. That card is the same "back preview" motion the
Android system Settings app uses. The mismatch makes the chat screen feel unfinished.

Confirmed on the Pixel (Android 17, gesture navigation, build `e3cf75722`): holding a back
swipe mid-way on Settings shows the shrunken card; the same hold inside a chat shows
the page fully static.

The cause is the unconditional `canPop: false`:

```dart
// lib/app/layouts/conversation_view/pages/conversation_view.dart:274-295 — current
          child: PopScope(
            canPop: false,
            onPopInvokedWithResult: <T>(bool didPop, T? result) async {
              if (didPop) return;
              if (controller.inSelectMode.value) {
                controller.inSelectMode.value = false;
                controller.selected.clear();
                return;
              }
              if (controller.showAttachmentPicker.value) {
                controller.showAttachmentPicker.value = false;
                controller.updateWidgets<ConversationTextField>(null);
                return;
              }
              if (LifecycleSvc.isBubble) {
                SystemNavigator.pop();
              }
              controller.close();
              if (LifecycleSvc.isBubble) return;
              return Navigator.of(context).pop();
            },
            child: Actions(
```

Flutter only animates a route with the gesture when `ModalRoute.popGestureEnabled` is true,
and that getter returns false whenever any `PopScope` on the route has `canPop: false`
(`~/sdk/flutter/packages/flutter/lib/src/widgets/routes.dart:1923`). The predictive-back
builder checks exactly that (`predictive_back_page_transitions_builder.dart:224`). So the
transition never sees the gesture. The pop happens programmatically on release, and the
builder falls back to `FadeForwardsPageTransitionsBuilder`.

No transition code needs to change. The app's Material route is already
`MaterialPageRoute` (`lib/app/wrappers/theme_switcher.dart:24`). Flutter 3.47.4's default
Android builder is `PredictiveBackPageTransitionsBuilder`
(`~/sdk/flutter/packages/flutter/lib/src/material/page_transitions_theme.dart:766`), and
FlexColorScheme leaves `pageTransitionsTheme` at that default. The only job is to stop
vetoing the gesture when there is nothing to intercept.

## Target

`canPop` is `true` unless back has local work to do: leaving select mode, closing the
attachment picker, or closing the chat bubble. When the route really pops, by gesture,
button, Escape or programmatically, `controller.close()` runs once from the `didPop` branch.

```dart
// target — conversation_view.dart, inside the Obx builder that starts at :244
        final body = Actions(
          actions: _actionsMap,
          // Focus lands inside these Actions even before the composer is focused, so Escape resolves GoBackIntent.
          child: FocusScope(
            autofocus: true,
            child: BBScaffold(
              backgroundColor: windowEffect != WindowEffect.disabled
                  ? Colors.transparent
                  : (material ? colorScheme.surfaceContainer : colorScheme.surface),
              extendBodyBehindAppBar: !material,
              appBar: _appBar,
              body: _bodyContent,
            ),
          ),
        );

        return Theme(
          data: material
              ? baseTheme
              : baseTheme.copyWith(
                  primaryColor: bubbleColor,
                  colorScheme: colorScheme.copyWith(
                    primary: bubbleColor,
                    onPrimary: onBubbleColor,
                  ),
                ),
          child: Obx(() => PopScope(
                canPop: !controller.inSelectMode.value &&
                    !controller.showAttachmentPicker.value &&
                    !LifecycleSvc.isBubble,
                onPopInvokedWithResult: <T>(bool didPop, T? result) {
                  if (didPop) {
                    controller.close();
                    return;
                  }
                  if (controller.inSelectMode.value) {
                    controller.inSelectMode.value = false;
                    controller.selected.clear();
                    return;
                  }
                  if (controller.showAttachmentPicker.value) {
                    controller.showAttachmentPicker.value = false;
                    controller.updateWidgets<ConversationTextField>(null);
                    return;
                  }
                  if (LifecycleSvc.isBubble) {
                    SystemNavigator.pop();
                    controller.close();
                  }
                },
                child: body,
              )),
        );
```

Why each piece:

- **Inner `Obx` around `PopScope` only.** `inSelectMode` and `showAttachmentPicker` are
  `RxBool`s (`lib/services/ui/chat/conversation_view_controller.dart:54`, `:79`). Reading them
  inside the inner `Obx` subscribes only that `Obx`, so toggling select mode rebuilds the
  `PopScope` and nothing else. `body` is built once by the outer builder and passed in as
  the same instance, so the scaffold is not rebuilt. Do NOT read them in the outer `Obx`
  (`:244`). That would re-render the whole themed page on every toggle.
- **`LifecycleSvc.isBubble` is a plain `bool`** (`lib/services/backend/lifecycle/lifecycle_service.dart:22`),
  set once at launch. It is fine to read it in the `canPop` expression.
- **`close()` moves into `didPop`.** `Navigator.pop` (header back button), `maybePop`
  (Escape via `GoBackAction`, `lib/services/backend_ui_interop/intents.dart:362`) and a
  committed predictive gesture all reach `onPopInvokedWithResult(true, …)`
  (`navigator.dart:3372`, `:5660`). Route *removal* by `pushAndRemoveUntil` does not, so
  opening another chat on top keeps its existing close path
  (`navigator_service.dart:115-118`).
- **The old explicit `Navigator.of(context).pop()` is gone.** With `canPop: true` the
  framework pops the route itself. In the three blocked cases the old code never reached
  that line.
- **`close()` may now run twice** on the header back button path, because
  `material_header.dart:59` calls it before `Navigator.pop`. That was already true for the
  archive and delete paths (`material_header.dart:124`, `:155`). It is idempotent:
  `updateSmartReplyLayout` no-ops on an unchanged height (`conversation_view_controller.dart:319-322`),
  `ChatsSvc.setAllInactiveSync` re-clears already-null state (`chats_service.dart:1003-1023`),
  and `Get.delete` on an already-deleted tag returns false. Do not remove the header calls;
  they are out of scope.

## Repo conventions to follow

- Nested `Obx` scoping a reactive read to a small subtree is the house pattern; the outer
  builder at `conversation_view.dart:244` is itself an `Obx`.
- `PopScope` + `onPopInvokedWithResult` with the generic `<T>(bool didPop, T? result)`
  signature is used everywhere in `lib/app/layouts`; keep that signature.
- No comments are needed; the repo's comment policy (`~/.claude/CLAUDE.md` → Comments) blocks
  narration. If you feel one is needed, the only acceptable one is a single line above `canPop`:
  `// canPop: false disables predictive back for the whole route.`

## Steps

1. In `lib/app/layouts/conversation_view/pages/conversation_view.dart`, inside the `Obx`
   builder that begins at line 244, insert `final body = Actions(...);` immediately before
   `return Theme(` (currently line 264). Move the existing `Actions(...)` subtree from lines
   295-309 into it, unchanged.
2. Replace the `child: PopScope(...)` at lines 274-310 with
   `child: Obx(() => PopScope(... child: body))` exactly as in **Target**.
3. Remove `async` from the `onPopInvokedWithResult` closure; nothing in it awaits.
4. Run the mechanical checks below. If the analyzer flags an unused import, it will only
   be one this edit orphaned. Remove it only if it is.

## Boundaries

- Do NOT change any `PageTransitionsTheme`, route builder, or `ThemeSwitcher`.
- Do NOT touch `material_header.dart`, `cupertino_header.dart`, `samsung_header.dart` or
  `NavigationService`.
- Do NOT change the tablet-mode `PopScope`s in `conversation_list.dart:290-353`.
- Do NOT add a custom gesture detector or hand-roll a predictive transition. The framework's
  builder is the target.
- If the code at the cited lines no longer matches the excerpt (drift since `e3cf75722`), STOP
  and report.

## Verification

- **Mechanical**:
  - `export PATH="/home/james/sdk/flutter/bin:$PATH" && flutter analyze --no-pub --no-fatal-infos`.
    The result must have 0 errors and 0 warnings, and no new info in `conversation_view.dart`.
    Compare that file's infos with the same file at `e3cf75722`; don't compare total counts.
  - `flutter build linux --debug --no-pub` must compile. Two pre-existing CMake warnings are normal.
  - Pixel install (release, prod flavor): `flutter build apk --release --flavor prod
    -Porg.gradle.workers.max=2 -Pkotlin.daemon.jvm.options=-Xmx1536m`. Then run
    `(cd android && ./gradlew --stop)`, and install only if the build printed `✓ Built`.
- **Feel check** on the Pixel, Material skin, gesture navigation:
  - Open a chat and drag slowly from the left edge. The chat shrinks to a rounded card that
    follows the finger, and the chat list is visible behind it, as in Settings. Drag back to
    the edge and release: the gesture cancels, and the chat springs back to full size with no
    flicker.
  - Release mid-swipe: the card completes the exit. The chat list underneath is interactive
    immediately; opening another chat right away works and shows that chat's messages.
  - Long-press a message to enter select mode, then swipe back. There is no card preview, and
    release exits select mode while staying in the chat. Swipe again and the preview returns.
  - Open the attachment picker and swipe back: it closes, and the chat stays.
  - Tap the header back arrow: the page exits with the regular fade, and the chat is no
    longer marked active (a new message in it posts a notification).
  - Desktop/Linux build: Escape inside a chat still returns to the list.
- **Done when**: a slow edge swipe inside any chat shows the same shrinking card as
  Settings, and select mode, the attachment picker and bubble mode still swallow back
  exactly as before.
