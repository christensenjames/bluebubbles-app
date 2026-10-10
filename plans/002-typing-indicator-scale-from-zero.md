# 002 — Stop the typing indicator from scaling out of nothing

- **Status**: DONE
- **Commit**: 831f70d89
- **Severity**: HIGH
- **Category**: Physicality & origin
- **Estimated scope**: 1 file, ~12 lines

## Problem

The typing bubble is a content-bearing surface that appears by inflating from zero size.
Nothing in the physical world appears from nothing; a surface should enter at
`scale(0.9-0.97)` with opacity, not `scale(0)`.

The controller is driven from 0 and fed straight into a `ScaleTransition`:

```dart
// lib/app/layouts/conversation_view/widgets/message/typing/typing_indicator.dart:44-52 — current
_scaleController = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 280),
);
_scaleAnimation = CurvedAnimation(
  parent: _scaleController,
  curve: Curves.easeOutBack,
  reverseCurve: Curves.easeIn,
);
```

```dart
// lib/app/layouts/conversation_view/widgets/message/typing/typing_indicator.dart:62-65 — current
_isShowing = _currentVisibility;
if (_isShowing) {
  _scaleController.forward(from: 0.0);
}
```

```dart
// lib/app/layouts/conversation_view/widgets/message/typing/typing_indicator.dart:145-149 — current
? ScaleTransition(
    scale: _scaleAnimation,
    // Anchor the grow/shrink at the bottom-left — the tail of the
    // speech bubble — so it feels like a real iMessage bubble.
    alignment: Alignment.bottomLeft,
```

The `alignment: Alignment.bottomLeft` is correct and deliberate — it is documented and
must be preserved. The defect is the 0.0 starting scale, compounded by `easeOutBack`
overshoot on top of it: the bubble pops out of a point and then springs past its size.

280ms is also above the 125-200ms budget for a small surface like this.

## Target

The bubble enters at 92% size with a fade, over 200ms, with a strong ease-out and no
overshoot. The bottom-left anchor stays exactly as it is.

```dart
// target — typing_indicator.dart initState
_scaleController = AnimationController(
  vsync: this,
  duration: const Duration(milliseconds: 200),
);
_scaleAnimation = Tween<double>(begin: 0.92, end: 1.0).animate(
  CurvedAnimation(
    parent: _scaleController,
    curve: const Cubic(0.23, 1.0, 0.32, 1.0),
    reverseCurve: const Cubic(0.23, 1.0, 0.32, 1.0),
  ),
);
_fadeAnimation = CurvedAnimation(
  parent: _scaleController,
  curve: const Cubic(0.23, 1.0, 0.32, 1.0),
);
```

```dart
// target — typing_indicator.dart build
? FadeTransition(
    opacity: _fadeAnimation,
    child: ScaleTransition(
      scale: _scaleAnimation,
      // Anchor the grow/shrink at the bottom-left — the tail of the
      // speech bubble — so it feels like a real iMessage bubble.
      alignment: Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 5),
        child: _buildBubble(context),
      ),
    ),
  )
```

The field type changes from `CurvedAnimation` to `Animation<double>` for `_scaleAnimation`;
declare `late final Animation<double> _fadeAnimation;` beside it.

## Repo conventions to follow

- This file already documents *why* a motion decision was made, in a short comment above
  the property it explains (`typing_indicator.dart:147-148`). Keep that comment verbatim,
  and do not add narration to the values that need none.
- Exemplar for a scale entrance that starts from a fraction rather than zero:
  `lib/app/layouts/conversation_view/widgets/message/popup/message_popup.dart:275-282`
  uses `Tween<double>(begin: 0.8, end: 1)` — same shape, different begin value.
- The status listener at `typing_indicator.dart:56-60` removes the content from the tree on
  `AnimationStatus.dismissed`; it must keep working, so the reverse direction must still
  reach 0.0 controller value (it will — only the mapped scale changes, not the controller).

## Steps

1. Change the `_scaleController` duration from 280ms to 200ms.
2. Replace the `_scaleAnimation` assignment with the `Tween(0.92 → 1.0)` form above, using
   `Cubic(0.23, 1.0, 0.32, 1.0)` for both curve and reverseCurve.
3. Add the `_fadeAnimation` field and assign it as shown.
4. Update the field declaration for `_scaleAnimation` to `late final Animation<double>`
   (it is currently typed as the `CurvedAnimation` it was assigned).
5. In `build`, wrap the existing `ScaleTransition` in a `FadeTransition` driven by
   `_fadeAnimation`, preserving the `alignment`, its comment, and the `Padding` child
   exactly.
6. Leave the outer `AnimatedSize(duration: 200ms, curve: Curves.easeOut)` at
   `typing_indicator.dart:141-143` alone — it animates the space the bubble occupies, and
   its duration already matches the new controller.

## Boundaries

- Do NOT change `alignment: Alignment.bottomLeft` or delete its comment.
- Do NOT touch `_buildBubble`, `AnimatedDot`, or the dot animation below line 159.
- Do NOT change the visibility worker or the status listener.
- Do NOT add dependencies.
- If `_scaleAnimation` has other readers than the `ScaleTransition` in `build`, STOP and
  report.

## Verification

- **Mechanical**: `flutter analyze --no-fatal-infos` with zero `error` lines. The field
  retype in step 4 is the likely source of an analyzer error if step 2 is done alone.
- **Feel check**: run the Linux build, open a chat, and have someone start typing:
  - The bubble appears at nearly full size and fades in — it must never look like it grows
    out of a point.
  - It does not overshoot and settle back; the previous `easeOutBack` bounce is gone.
  - When typing stops, the bubble shrinks toward its bottom-left tail and the row collapses
    without a jump.
  - Start and stop typing rapidly: the bubble retargets mid-animation rather than
    restarting from the beginning.
- **Done when**: the entrance starts at 92% with opacity 0, runs 200ms, and the
  bottom-left anchor is visibly preserved.
