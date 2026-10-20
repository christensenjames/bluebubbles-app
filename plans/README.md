# Animation plans

Produced by the `improve-animations` skill against commit `831f70d89`. Each plan is
self-contained: exact file, exact current code, exact target values, and a feel check.
Findings were vetted at their `file:line` before a plan was written for them.
The `Cubic(0.23, 1.0, 0.32, 1.0)` these plans prescribe was later replaced by the M3 tokens
(`Easing.emphasizedDecelerate`, `Durations.*`) in `d97642b38`; the plans are kept as written.

| # | Title | Severity | Category | Status |
| --- | --- | --- | --- | --- |
| [001](001-shorten-received-message-insertion.md) | Shorten the received-message insertion animation | HIGH | Purpose & frequency | DONE |
| [002](002-typing-indicator-scale-from-zero.md) | Stop the typing indicator from scaling out of nothing | HIGH | Physicality & origin | DONE |
| [003](003-ease-in-on-text-field-pickers.md) | Replace ease-in on the two text-field pickers | HIGH | Easing & duration | DONE |
| [004](004-reaction-details-route-duration.md) | Cut the reaction-details route transition to 300ms | HIGH | Purpose & frequency | DONE |
| [005](005-predictive-back-on-conversation-view.md) | Let the conversation screen follow the predictive back gesture | HIGH | Interruptibility | DONE |
| [006](006-predictive-back-on-chat-list.md) | Let back on the chat list peek home, and peek out of Archived / Unknown Senders | MEDIUM | Interruptibility | DONE |
| [007](007-chat-creator-route-exit.md) | Give chats opened from the chat creator a real exit transition | MEDIUM | Missed opportunity | DONE (device check pending) |
| — | Back moves like the system Settings app: a back swipe shrinks the page into a card over the dimmed, shrunken previous page, and on release the card fades while the previous page grows back; the arrow moves the page 96dp right as it fades. Copied from AOSP `DefaultCrossActivityBackAnimation` and `activity_close_{enter,exit}.xml` (`SystemBackPageTransitionsBuilder`, set in `main.dart`); done inline at James's request, no plan file | MEDIUM | Easing & duration | DONE |

## Recommended order

003 → 004 → 002 → 001.

003 is two lines and touches nothing else. 004 is one file. 002 is confined to one widget
but changes a field's type, so it wants a clean analyzer run of its own. 001 is last
because it changes a shared config class and a method signature, and because its feel check
depends on receiving a real message.

## Dependencies

None of the four depend on each other. They touch disjoint files:

- 001 — `message_list_animation_config.dart`, `message_animation_orchestrator.dart`, `messages_view.dart`
- 002 — `typing_indicator.dart`
- 003 — `text_field_component.dart`, `text_field_emoji_picker_section.dart`
- 004 — `reaction.dart`

One soft overlap: 001 introduces `MessageListAnimationConfig.strongEaseOut` with the value
`Cubic(0.23, 1.0, 0.32, 1.0)`, and 002-004 write that same literal inline. Consolidating
the four into a shared motion-token file was left as a deliberate follow-up. It has since
been surveyed: the repo's `lib/app/components/m3e/` layer already defines
`M3EMotion.spatialFast` as 200ms + `emphasizedDecelerate`, which is the same value chosen
by ear here, so the consolidation target is that token rather than a new file. Shapes and
spacing are deliberately NOT migrated — see the decision recorded in `CHANGELOG.md`.

## Not planned

Vetted and rejected: the in-app `reduceMotion` setting is *not* an under-applied global.
`lib/app/layouts/settings/pages/misc/misc_panel.dart:196` subtitles it "Keeps GIFs paused
until you hover over them", so its single render-path usage at `image_viewer.dart:158` is
the documented scope, not a gap.

## Carried-forward findings — swept 2026-09-11

The audit's unvetted remainder was swept and resolved without further plans; the fixes
landed directly in `3412641ac` and `5a29e8a8d`.

- Fixed: the ease-in cluster (chat-creator chip rows, cupertino URL preview, fullscreen
  arrow-key navigation, attachment picker, message-list fade), the 500ms-vs-400ms split
  inside the message popup, and the `animated_dropdown_menu.dart` scale-from-zero.
- Rejected as by-design: the two scroll-driven header titles (scroll-linked, not
  time-based — the late fade stops the collapsed title colliding with the expanded one);
  the `bubble_effects.dart` slam/loud wind-up (acceleration is the physics of an impact).
- Rejected as mis-attributed: `Obx` wrapping `AnimatedSize` in message-list rows. Flutter
  preserves `State` across a rebuild of the same widget type at the same position, so
  `AnimatedSize` retargets mid-flight rather than restarting. None of the three sites
  carries a `key`.
- Left alone on purpose: `reaction_holder.dart:37-40` still scales from zero with
  `easeOutBack`. A 25px tapback badge landing on a message is an object, not a surface,
  and the pop is the product's signature.

## Predictive back — written 2026-10-19 against `e3cf75722`

Recommended order: 005 → 007 → 006.

Flutter 3.47.4 already defaults Android `MaterialPageRoute`s to
`PredictiveBackPageTransitionsBuilder`, the same back-preview card the system Settings app
uses. Settings pages in the app already show it. These three plans remove the places that
switch it off. None of them changes a transition builder.

- 005 is the high-frequency fix and stands alone (`conversation_view.dart` only).
- 007 depends on 005 for its gesture preview. Its button-back fade works without 005.
  It touches `theme_switcher.dart`, `chat_creator.dart` and `chat_creator_controller.dart`.
- 006 is independent in code (`conversation_list.dart`, `material_conversation_list.dart`,
  `samsung_conversation_list.dart`) but goes last. Root exit behaviour turned out unchanged
  on Android 17: the system still finishes `MainActivity`, exactly as it does for system
  Settings. See the corrected section in the plan.
- No file is shared between the three plans.

After 005-007 shipped, `main.dart` replaced Flutter's Android builder with
`SystemBackPageTransitionsBuilder` (see the inline row in the status table), which copies the
system's activity back motion. The statements above that the transition builder is unchanged
and that the button-back fade works without 005 are superseded.

Out of scope, noted only: the iOS skin's `CustomCupertinoPageTransition` route has no
edge-swipe-back gesture, and tablet split view uses GetX `Transition.rightToLeft` slides.
