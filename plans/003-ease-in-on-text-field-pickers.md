# 003 — Replace ease-in on the two text-field pickers

- **Status**: DONE
- **Commit**: 831f70d89
- **Severity**: HIGH
- **Category**: Easing & duration
- **Estimated scope**: 2 files, 2 lines

## Problem

`ease-in` starts slow. On UI that is *entering* in response to a tap, it delays the exact
moment the user is watching, and reads as lag rather than as motion. Both pickers hanging
off the message text field open with it.

```dart
// lib/app/layouts/conversation_view/widgets/text_field/text_field_component.dart:507-513 — current
AnimatedSize(
  duration: const Duration(milliseconds: 250),
  curve: Curves.easeIn,
  alignment: Alignment.bottomCenter,
  child: _showAttachmentPickerLocal
      ? AttachmentPicker(controller: controller!)
      : SizedBox(width: NavigationSvc.width(context)),
),
```

```dart
// lib/app/layouts/conversation_view/widgets/text_field/text_field_emoji_picker_section.dart:31-35 — current
return AnimatedSize(
  duration: const Duration(milliseconds: 250),
  curve: Curves.easeIn,
  alignment: Alignment.bottomCenter,
  child: Obx(() {
```

Both are tapped constantly while composing, and both are panels sliding up from the bottom
of the screen — the textbook case for ease-out.

The 250ms duration is fine; it sits inside the 150-250ms budget for this class of surface.
Only the curve is wrong. The `alignment: Alignment.bottomCenter` is also correct — these
grow upward from the bottom edge — and must be kept.

## Target

Identical in both files: a strong ease-out, everything else untouched.

```dart
// target — both files
AnimatedSize(
  duration: const Duration(milliseconds: 250),
  curve: const Cubic(0.23, 1.0, 0.32, 1.0),
  alignment: Alignment.bottomCenter,
```

`Cubic(0.23, 1.0, 0.32, 1.0)` is a strong ease-out; Flutter's built-in `Curves.easeOut`
(`Cubic(0.0, 0.0, 0.58, 1.0)`) is too weak to read as deliberate on a panel this size.

## Repo conventions to follow

- Curves are written inline at the animation site throughout this codebase; there is no
  shared motion-token file at the stamped commit. Write the `Cubic` literal inline in both
  places rather than introducing a constants file as part of this plan.
- If plan 001 has already landed, `MessageListAnimationConfig.strongEaseOut` holds this
  exact value — but it lives in the message-list config class and is not appropriate to
  import into the text field. Keep the literal.
- Exemplar of an inline custom curve already in the tree:
  `lib/app/layouts/conversation_view/widgets/message/popup/message_popup.dart:319-322`
  passes a non-built-in curve (`Sprung.underDamped`) directly to an `AnimatedSize`.

## Steps

1. In `text_field_component.dart:509`, replace `curve: Curves.easeIn,` with
   `curve: const Cubic(0.23, 1.0, 0.32, 1.0),`.
2. In `text_field_emoji_picker_section.dart:33`, make the identical replacement.
3. Verify no other `AnimatedSize` in
   `lib/app/layouts/conversation_view/widgets/text_field/` still uses `Curves.easeIn`:
   `grep -rn "Curves.easeIn" lib/app/layouts/conversation_view/widgets/text_field/`.
   If that returns hits beyond the two changed lines, list them in your report — do not fix
   them under this plan.

## Boundaries

- Do NOT change the durations.
- Do NOT change `alignment: Alignment.bottomCenter` in either file.
- Do NOT touch the `child:` expressions, the `Obx`, or the picker widgets themselves.
- Do NOT create a shared curve/token file — that is a separate consolidation decision.
- Do NOT fix `Curves.easeIn` anywhere outside these two lines; other sites are covered by
  their own findings and some are legitimate exits.

## Verification

- **Mechanical**: `flutter analyze --no-fatal-infos` with zero `error` lines.
- **Feel check**: run the Linux build, open a chat, and:
  - Tap the attachment button. The picker should start moving immediately and decelerate
    into place; the first ~80ms must not look stalled.
  - Tap the emoji button and confirm the same.
  - Toggle each open and closed several times quickly — the panel should retarget rather
    than look like it restarts.
  - Compare against a message-list insertion, which already uses ease-out: the two should
    now feel like the same app.
- **Done when**: neither picker uses `Curves.easeIn`, both still grow from the bottom edge,
  and both still take 250ms.
