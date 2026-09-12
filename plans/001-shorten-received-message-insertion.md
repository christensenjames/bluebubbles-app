# 001 — Shorten the received-message insertion animation

- **Status**: DONE
- **Commit**: 831f70d89
- **Severity**: HIGH
- **Category**: Purpose & frequency / Easing & duration
- **Estimated scope**: 3 files, ~20 lines

## Problem

Every message inserted into the conversation list — sent *and* received — animates for
475ms. Receiving a message is a 100+/day event, and 475ms is well past the 300ms budget
for UI motion.

The long duration has a documented reason, but it applies only to outgoing messages:

```dart
// lib/app/layouts/conversation_view/pages/handlers/message_list_animation_config.dart:6-10 — current
/// Duration for new message insertion animations (slide + size + fade).
///
/// Slightly longer duration delays the outgoing fade-in handoff so the
/// temporary send bubble and list row don't visually overlap as tightly.
static const Duration insertionDuration = Duration(milliseconds: 475);
```

Received messages inherit that duration without the handoff constraint that justifies it:

```dart
// lib/app/layouts/conversation_view/pages/handlers/message_animation_orchestrator.dart:101 — current
Duration getInsertionDuration() => MessageListAnimationConfig.insertionDuration;
```

```dart
// lib/app/layouts/conversation_view/pages/messages_view.dart:456-464 — current
// Mark this message for animation (all new messages)
animationOrchestrator.markAnimating(message);

// Use insertItem to animate the list sliding up to make space (all messages)
final duration = animationOrchestrator.getInsertionDuration();
_listKey.currentState?.insertItem(
  insertIndex,
  duration: duration,
);
```

The orchestrator already separates the two directions — `buildSentMessageAnimation` at
`message_animation_orchestrator.dart:37` and `buildReceivedMessageAnimation` at `:74` — so
only the duration is shared.

A second, smaller issue in the same file: `Curves.easeOut` is Flutter's weak built-in
ease-out (`Cubic(0.0, 0.0, 0.58, 1.0)`). Deliberate UI motion wants a strong ease-out.

## Target

Received messages animate for **200ms**; sent messages keep **475ms** and their documented
handoff. Both use a strong ease-out curve.

```dart
// target — lib/app/layouts/conversation_view/pages/handlers/message_list_animation_config.dart
/// Strong ease-out for entering UI. Flutter's Curves.easeOut is
/// Cubic(0.0, 0.0, 0.58, 1.0), which is too weak to read as deliberate.
static const Curve strongEaseOut = Cubic(0.23, 1.0, 0.32, 1.0);

/// Duration for outgoing message insertion (slide + size + fade).
///
/// Slightly longer duration delays the outgoing fade-in handoff so the
/// temporary send bubble and list row don't visually overlap as tightly.
static const Duration sentInsertionDuration = Duration(milliseconds: 475);

/// Duration for incoming message insertion. Receiving is a high-frequency
/// event with no send-bubble handoff, so it stays inside the 300ms UI budget.
static const Duration receivedInsertionDuration = Duration(milliseconds: 200);

static const Curve insertionSlideCurve = strongEaseOut;
static const Curve insertionSizeCurve = strongEaseOut;
static const Curve insertionFadeCurve = strongEaseOut;
```

```dart
// target — lib/app/layouts/conversation_view/pages/handlers/message_animation_orchestrator.dart
/// Get the insertion duration for a new message.
Duration getInsertionDuration({required bool isFromMe}) => isFromMe
    ? MessageListAnimationConfig.sentInsertionDuration
    : MessageListAnimationConfig.receivedInsertionDuration;
```

```dart
// target — lib/app/layouts/conversation_view/pages/messages_view.dart:460
final duration = animationOrchestrator.getInsertionDuration(isFromMe: message.isFromMe ?? false);
```

## Repo conventions to follow

- All message-list motion values already live in
  `lib/app/layouts/conversation_view/pages/handlers/message_list_animation_config.dart`
  as `static const` fields with a doc comment explaining *why* the value is what it is.
  Extend that class; do not introduce a second config surface.
- Exemplar to imitate: `MessageListAnimationConfig.fadeInterval` at
  `message_list_animation_config.dart:22` — a named constant whose comment states the
  intent (`Fade interval for sent messages (0.9-1.0 of animation)`), referenced by name
  from the orchestrator rather than inlined.
- `Message.isFromMe` is a nullable `bool?` throughout this codebase; `message` is already
  in scope at `messages_view.dart:460`.

## Steps

1. In `message_list_animation_config.dart`, add the `strongEaseOut` constant, rename
   `insertionDuration` to `sentInsertionDuration` (keeping its existing doc comment), and
   add `receivedInsertionDuration` at 200ms with the comment shown above.
2. In the same file, point `insertionSlideCurve`, `insertionSizeCurve` and
   `insertionFadeCurve` at `strongEaseOut`. Leave `fadeInterval`,
   `sizeTransitionStartRatio`, `slideStartOffset` and `sizeTransitionAxisAlignment`
   untouched.
3. In `message_animation_orchestrator.dart:101`, change `getInsertionDuration()` to take a
   required named `bool isFromMe` and return the matching constant.
4. In `messages_view.dart:460`, pass `isFromMe: message.isFromMe ?? false`.
5. Grep for any other caller: `grep -rn "getInsertionDuration\|insertionDuration" lib`.
   Every hit must compile against the new signature. There was exactly one call site at
   the commit stamped above.

## Boundaries

- Do NOT change `buildSentMessageAnimation` or `buildReceivedMessageAnimation` structure —
  only the values they read.
- Do NOT touch `fadeInterval` or the size/slide geometry constants.
- Do NOT change any other file's durations; the other plans cover those.
- Do NOT add dependencies.
- If `insertionDuration` has other callers than the one listed, STOP and report.

## Verification

- **Mechanical**: `cd ~/Projects/bluebubbles-app && flutter analyze --no-fatal-infos` —
  zero `error` lines. Then `flutter build linux --release`, which must succeed.
- **Feel check**: run the Linux build, open a chat with an active conversation, and have a
  message sent to you:
  - The incoming bubble settles noticeably faster than before and is readable almost
    immediately; it should not visibly "grow" while you are already reading it.
  - Send a message yourself: the temporary send bubble still hands off to the list row
    without the two overlapping — that handoff is what the 475ms protects, and it must not
    regress.
  - Receive several messages in quick succession: each animation finishes before the next
    starts, with no visible pile-up.
- **Done when**: incoming insertion measures 200ms, outgoing stays 475ms, and the
  send-bubble handoff still looks clean.
