# 006 — Let back on the chat list peek home, and peek out of Archived / Unknown Senders

- **Status**: DONE
- **Commit**: e3cf75722
- **Severity**: MEDIUM
- **Category**: Interruptibility
- **Estimated scope**: 3 files, ~25 lines

## Problem

The Material and Samsung chat lists veto every back gesture with an unconditional
`canPop: false`. That has two visible effects:

1. **Main chat list.** Android's back-to-home animation never plays. On it, the app shrinks
   into a card and the home screen shows behind it, following the finger. Swiping back from
   the list shows only the arrow chip, then the app vanishes on release. Confirmed on the
   Pixel (Android 17, gesture navigation, `e3cf75722`): a held mid-swipe on the chat list
   left the list fully static.
2. **Archived and Unknown Senders.** These lists are pushed routes that render the same
   widget (`conversation_list.dart:275` returns the skin widget directly). The same veto
   kills their in-app peek back to the main list. Settings pages one tap away do peek.

```dart
// lib/app/layouts/conversation_list/pages/material_conversation_list.dart:54-71 — current
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: <T>(bool didPop, T? other) {
        if (didPop) return;
        if (controller.selectedChats.isNotEmpty) {
          controller.clearSelectedChats();
          return;
        } else if (controller.showArchivedChats || controller.showUnknownSenders) {
          // Pop the current page
          Navigator.of(context).pop();
        } else {
          // Pop the app to exit the app
          SystemNavigator.pop();
        }
      },
      child: Container(
```

```dart
// lib/app/layouts/conversation_list/pages/samsung_conversation_list.dart:58-75 — current
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: <T>(bool didPop, T? other) {
        if (didPop) return;
        if (controller.selectedChats.isNotEmpty) {
          controller.clearSelectedChats();
          return;
        } else if (controller.showArchivedChats || controller.showUnknownSenders) {
          // Pop the current page
          Navigator.of(context).pop();
        } else {
          // Pop the app to exit the app
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
```

The two non-selection branches only re-implement what the platform does by default: pop
the pushed route, or leave the app. Flutter disables gesture tracking for any route
carrying a `canPop: false` scope (`~/sdk/flutter/packages/flutter/lib/src/widgets/routes.dart:1923`).
At the root, the same flag makes the framework tell Android it handles back itself. Android
then never gets to play its home preview.

`selectedChats` is a plain `List<Chat>` (`conversation_list.dart:40`), so `canPop` currently
has nothing reactive to follow.

## Target

Back is vetoed only while chats are selected. Otherwise the framework pops the pushed
Archived and Unknown Senders routes with the predictive card, and Android handles back on
the root list with its back-to-home animation.

```dart
// target — conversation_list.dart, ConversationListController fields (after line 40)
  final List<Chat> selectedChats = [];
  final RxBool hasSelection = false.obs;
```

```dart
// target — conversation_list.dart, updateSelectedChats (line 46)
  void updateSelectedChats() {
    hasSelection.value = selectedChats.isNotEmpty;
    if (SettingsSvc.settings.skin.value == Skins.Material) {
      updateWidgets<MaterialHeader>(null);
      updateMaterialFAB();
    } else if (SettingsSvc.settings.skin.value == Skins.Samsung) {
      updateWidgets<SamsungFooter>(null);
      updateWidgets<ExpandedHeaderText>(null);
    }
  }
```

```dart
// target — material_conversation_list.dart build (Samsung is identical; its child is the Scaffold)
  @override
  Widget build(BuildContext context) {
    final page = Container(
      // ... the existing Container subtree from lines 71-175, unchanged ...
    );
    return Obx(() => PopScope(
          canPop: !controller.hasSelection.value,
          onPopInvokedWithResult: <T>(bool didPop, T? other) {
            if (didPop) return;
            controller.clearSelectedChats();
          },
          child: page,
        ));
  }
```

Every mutation of `selectedChats` already ends in `updateSelectedChats()`. There are four
sites: `conversation_list.dart:56-63` (`clearSelectedChats`), `:86-94` (`selectChats`), and
`widgets/tile/list_item.dart:90-96` (add and remove). Setting `hasSelection` inside
`updateSelectedChats` therefore covers them all without touching the call sites. Verify that
with `grep -rn "selectedChats\.\(add\|remove\|clear\|addAll\)" lib` before editing. If a fifth
mutation exists that does not call `updateSelectedChats()`, STOP and report.

### Root exit behaviour (corrected after implementation)

Today, back on the main list calls `SystemNavigator.pop()`, which **finishes** `MainActivity`.
This was observed on the Pixel: after a back swipe from the list, the activity record was gone
from `dumpsys activity activities`, while the task stayed in recents and the process (pid
31320) stayed alive.

This plan originally predicted that `canPop: true` would move the task to the back instead.
On the Pixel (Android 17) that prediction was wrong. With the framework no longer claiming
back, the system takes over (`ShellBackPreview: … mType=TYPE_RETURN_TO_HOME`) and still
finishes the activity (`wm_finish_activity … app-request`). System Settings logs the identical
pair for the same gesture. So exit behaviour is unchanged. The gain is that the system,
not the app, now owns the gesture and plays its own back-to-home animation.

## Repo conventions to follow

- `RxBool foo = false.obs` fields on controllers, read under `Obx`, are the house pattern; e.g.
  `inSelectMode` at `lib/services/ui/chat/conversation_view_controller.dart:54`.
- Build the heavy subtree once outside the `Obx` and pass it in as `child`. Only `PopScope`
  rebuilds when the selection empties or fills. Never read `hasSelection` outside that inner
  `Obx`.
- Keep the generic `<T>(bool didPop, T? other)` callback signature used across
  `lib/app/layouts`.

## Steps

1. `lib/app/layouts/conversation_list/pages/conversation_list.dart`: add
   `final RxBool hasSelection = false.obs;` directly below `selectedChats` (line 40). Make
   `hasSelection.value = selectedChats.isNotEmpty;` the first line of `updateSelectedChats()`
   (line 46).
2. `lib/app/layouts/conversation_list/pages/material_conversation_list.dart`: hoist the
   `Container(...)` passed as `child:` (lines 71-175) into `final page = Container(...);`
   at the top of `build`. Replace the `PopScope` at lines 56-70 with the **Target** form.
3. `lib/app/layouts/conversation_list/pages/samsung_conversation_list.dart`: hoist the
   `Scaffold(...)` passed as `child:` (lines 75-196) into `final page = Scaffold(...);`
   the same way. Replace the `PopScope` at lines 60-74 with the **Target** form.
4. If `flutter analyze` now reports `package:flutter/services.dart` as unused or unnecessary
   in either skin file (its only visible use was `SystemNavigator`), remove that import.
   Otherwise leave it.

## Boundaries

- Do NOT touch `cupertino_conversation_list.dart`; it has no `PopScope` today.
- Do NOT touch the tablet-mode `PopScope`s in `conversation_list.dart:290-353`.
- Do NOT touch the `PopScope(canPop: false)` around setup/splash at `lib/main.dart:762`.
- Do NOT add any `MethodChannel`/Kotlin change or override `onBackPressed`. The manifest
  comment at `android/app/src/main/AndroidManifest.xml:65-72` forbids it.
- Do NOT change `clearSelectedChats`, `selectChats` or `list_item.dart` beyond what step 1
  states.
- If code at the cited lines differs from the excerpts (drift since `e3cf75722`), STOP and
  report.

## Verification

- **Mechanical**:
  - `export PATH="/home/james/sdk/flutter/bin:$PATH" && flutter analyze --no-pub --no-fatal-infos`.
    The result must have 0 errors, 0 warnings, and no new infos in the three touched files
    (compare against the same files at `e3cf75722`, not total counts).
  - `flutter build linux --debug --no-pub` must compile.
  - Pixel: `flutter build apk --release --flavor prod -Porg.gradle.workers.max=2
    -Pkotlin.daemon.jvm.options=-Xmx1536m`, then `(cd android && ./gradlew --stop)`; install
    only if the output contains `✓ Built`.
- **Feel check** on the Pixel, Material skin, gesture navigation:
  - On the main chat list, drag slowly from the left edge. The app shrinks into a card with
    the home screen behind it, following the finger. Drag back and release: it cancels
    cleanly. Release mid-swipe: the app goes home.
  - After going home that way, `adb logcat -d | grep 'ShellBackPreview: Received'` shows
    `mType=TYPE_RETURN_TO_HOME` (or `TYPE_CROSS_TASK` when another app's task is behind).
    Either one means the system, not the app, handled back.
  - Long-press a chat to select it, then swipe back. There is no home preview, and release
    clears the selection while staying in the app. Swipe again and the preview returns. Repeat
    with ⋮ → Select all.
  - ⋮ → Archived, then drag back slowly. The Archived list shrinks into a card with the main
    list behind it, as in Settings. Same check for Unknown Senders if it is enabled.
  - Switch to the Samsung skin and repeat the first and third checks.
  - Messages still arrive after leaving this way (send one from another device; the
    notification posts).
- **Done when**: back from the root list plays Android's home preview, back from Archived and
  Unknown Senders plays the in-app card, and a non-empty selection still turns back into
  "clear selection".
