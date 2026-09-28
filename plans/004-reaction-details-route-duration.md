# 004 — Cut the reaction-details route transition to 300ms

- **Status**: DONE
- **Commit**: 831f70d89
- **Severity**: HIGH
- **Category**: Purpose & frequency
- **Estimated scope**: 1 file, 2 lines

## Problem

Tapping a reaction on a message opens the reaction-details view through a half-second
slide. Reading who reacted is a quick, frequent inspection — half a second of transition
sits between the tap and the information every single time.

```dart
// lib/app/layouts/conversation_view/widgets/message/reaction/reaction.dart:138-147 — current
Navigator.push(
  context,
  PageRouteBuilder(
    transitionDuration: const Duration(milliseconds: 500),
    pageBuilder: (routeCtx, animation, secondaryAnimation) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0.0, 1.0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
```

The direction is right — it rises from the bottom like a sheet, and `easeOut` is the right
family. Only the duration is out of band: 500ms is the ceiling of the modal/drawer budget,
and this surface is neither large nor rarely used.

## Target

300ms, with a strong ease-out replacing the weak built-in. Geometry unchanged.

```dart
// target — reaction.dart:141 and :147
transitionDuration: const Duration(milliseconds: 300),
...
).animate(CurvedAnimation(parent: animation, curve: const Cubic(0.23, 1.0, 0.32, 1.0))),
```

`Curves.easeOut` is `Cubic(0.0, 0.0, 0.58, 1.0)`; the replacement decelerates harder, so
the sheet reads as settling rather than drifting even though it now takes less time.

## Repo conventions to follow

- `PageRouteBuilder` with an explicit `transitionDuration` and a hand-built
  `SlideTransition` is the established pattern for custom routes here; nine files use it.
  Keep the structure and change only the two values.
- The theme capture immediately above the `Navigator.push` (`reaction.dart:133-137`) exists
  because adaptive per-chat theming must be captured before the route is pushed. Leave it
  exactly as it is.
- If the route declares a `reverseTransitionDuration`, it must be changed to match; check
  the `PageRouteBuilder` arguments after `pageBuilder` (around `reaction.dart:174-178`)
  before finishing.

## Steps

1. Change `transitionDuration` at `reaction.dart:141` from 500ms to 300ms.
2. Replace `curve: Curves.easeOut` at `reaction.dart:147` with
   `curve: const Cubic(0.23, 1.0, 0.32, 1.0)`.
3. Read `reaction.dart:174-178`. If a `reverseTransitionDuration` is set to 500ms, set it
   to 300ms too. If it is absent, leave it absent — Flutter defaults it to
   `transitionDuration`.
4. Do not touch the `Theme(...)` wrapper or the colour-scheme overrides inside
   `pageBuilder`.

## Boundaries

- Do NOT change the slide direction or the `begin: Offset(0.0, 1.0)` geometry.
- Do NOT convert this to a different route type or to `showModalBottomSheet`.
- Do NOT change any other `PageRouteBuilder` in the repo.
- Do NOT alter the captured-theme logic at `reaction.dart:133-137`.

## Verification

- **Mechanical**: `flutter analyze --no-fatal-infos` with zero `error` lines.
- **Feel check**: run the Linux build, find a message carrying reactions, and tap one:
  - The details view arrives quickly enough that the tap feels like it opened something,
    not like it queued something.
  - The sheet still rises from the bottom edge and decelerates into place — no bounce, no
    overshoot.
  - Press back: the dismissal reads as symmetric with the entrance, not noticeably slower.
  - Tap a reaction, dismiss, and tap again immediately — the second open behaves like the
    first.
- **Done when**: the route transition measures 300ms in both directions and the sheet still
  slides up from the bottom.
