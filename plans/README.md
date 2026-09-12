# Animation plans

Produced by the `improve-animations` skill against commit `831f70d89`. Each plan is
self-contained: exact file, exact current code, exact target values, and a feel check.
Findings were vetted at their `file:line` before a plan was written for them.

| # | Title | Severity | Category | Status |
| --- | --- | --- | --- | --- |
| [001](001-shorten-received-message-insertion.md) | Shorten the received-message insertion animation | HIGH | Purpose & frequency | DONE |
| [002](002-typing-indicator-scale-from-zero.md) | Stop the typing indicator from scaling out of nothing | HIGH | Physicality & origin | DONE |
| [003](003-ease-in-on-text-field-pickers.md) | Replace ease-in on the two text-field pickers | HIGH | Easing & duration | DONE |
| [004](004-reaction-details-route-duration.md) | Cut the reaction-details route transition to 300ms | HIGH | Purpose & frequency | DONE |

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
the four into a shared motion-token file is a deliberate follow-up, not part of any plan
here — the repo has no token convention today, and inventing one mid-fix would put the
executor in the position of making a design decision.

## Not planned

Vetted and rejected: the in-app `reduceMotion` setting is *not* an under-applied global.
`lib/app/layouts/settings/pages/misc/misc_panel.dart:196` subtitles it "Keeps GIFs paused
until you hover over them", so its single render-path usage at `image_viewer.dart:158` is
the documented scope, not a gap.

Still unvetted, carried forward from the audit for a later pass: an ease-in cluster in the
chat-creator chip rows, the cupertino URL preview, fullscreen arrow-key navigation and two
scroll-driven header titles; the 500ms-vs-400ms split inside the message popup; two further
scale-from-zero surfaces (`animated_dropdown_menu.dart`, `reaction_holder.dart`); three
interruptibility cases where `Future.delayed` blocks a re-tap; and `Obx` wrapping
`AnimatedSize` inside message-list rows.
