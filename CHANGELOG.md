# Changelog

## 2026-09-11 — Emoji tapbacks end-to-end, animation audit, desktop layout fixes

### Arbitrary emoji tapbacks (iOS 18+ reactions)

Newer emoji reactions rendered as the literal text `null`. Traced end to end: the emoji
never left the Mac.

- Sequoia's `chat.db` carries `associated_message_emoji` (column 85), but the server never
  read it. `MessageTypeTransformer.ts:37-40` fell back to `dbValue.toString()` for unmapped
  ids, so the client received `associatedMessageType: "2006"` and nothing else.
- In the app, `reaction_helpers.dart:6-27` knows six reaction strings;
  `extensions.dart:404` looked up `reactionToVerb["2006"]` → null and `:451` interpolated
  that into the chat-list subtitle, which is the literal `null`. The bubble overlay
  separately dropped it at `message_holder_reactions.dart:39-41`.
- Receive path (app): `831f70d89` carries `associatedMessageEmoji` through the model,
  ObjectBox schema, helpers and chat preview.
- Send path: `365ed19ba` adds an emoji picker to the reaction bar and threads
  `reactionEmoji` through the send path. `15e0d891e` → `38b211d81` → `4ad67ed4c` iterated
  the remove control, ending as tap-the-highlighted-emoji.
- `85986da31` fixes an identity bug: two different emoji reactions from the same sender
  collapsed into one, because `associatedMessageEmoji` was missing from the reaction
  re-resolve match and from the animator key.
- Sibling repos: `bluebubbles-server` `11e4b0d2` (receive — entity column gated
  `isMinSequoia`, decoder, 2006/3006 in the type transformer, serializer key, response
  type) and `65f68c13` (send); `bluebubbles-helper` `991eccc`
  (`parseReactionType` emoji/-emoji → 2006/3006, `reactionToVerb:emoji:`, sets the outgoing
  `IMMessage` via `_associatedMessageEmoji:`).
- Upstream has tried twice and neither landed: kilabyte's app-only fix merged and was
  reverted the same day (`8dc75486` → `78b02187`), and ZachGarcia42's three-repo set
  (app #3162, server #839) is open but untouched since 2026-08-05.

### Animation audit

Audited with the `improve-animations` skill; every finding vetted at its `file:line` before
being acted on.

- `89639de61` — split `insertionDuration` into `sentInsertionDuration` 475ms and
  `receivedInsertionDuration` 200ms; introduced `strongEaseOut = Cubic(0.23, 1.0, 0.32, 1.0)`
  for the three insertion curves; typing indicator 280ms → 200ms entering at 92% instead of
  from nothing; reaction-details route 500ms → 300ms; both text-field pickers off `easeIn`.
- `3412641ac` — the anchored dropdown menu fed a bare `CurvedAnimation` to `ScaleTransition`,
  so it inflated out of a point, with `easeOutBack` springing it past its size. Now
  `Tween(0.92 → 1.0)`, 300/250ms → 200/150ms. The corner anchor is load-bearing, unchanged.
- `5a29e8a8d` — 14 defects across 12 files. `easeIn` on entering surfaces (chat-creator and
  recipient chip rows, attachment picker, message-list fade, URL-preview image, all four
  fullscreen arrow-key page turns); `easeOutBack` overshoot on content surfaces (long-press
  details menu, conversation peek, recording overlay, both edit fields, URL-preview icon);
  overshoot on a *translate* at `message_popup.dart:393`; durations popup 500/400 → 300 both
  (they were also 100ms out of sync), peek 400 → 300, recording overlay 500 → 300; the filter
  chip scaled from a literal point and now enters at 92%.
- Deliberately not changed: `reaction_holder.dart:37-40` still scales a tapback badge from
  zero with `easeOutBack` — a 25px badge landing on a message is an object, and the pop is
  the product's signature.
- Three scout findings rejected after reading the code: the `Obx(() => AnimatedSize(...))`
  "interruptibility" defects are not real (Flutter preserves `State` across a rebuild of the
  same widget type at the same position, so `AnimatedSize` retargets rather than restarting);
  the four scroll-driven header titles are scroll-linked, not time-based; the
  `bubble_effects.dart` slam/loud wind-up accelerates because that is the physics of an impact.

### Desktop layout (Material skin)

- `1c66005c0` — the conversation list cleared the custom title bar by padding its container
  down 30px, painting that strip in the list background rather than the header colour, so a
  black band sat above the left header only. The conversation pane instead grows its AppBar
  (`toolbarHeight: (kIsDesktop ? 25 : 0) + kToolbarHeight`) and insets the contents, which
  paints correctly. The list now does the same: `preferredSize` 60 → `kIsDesktop ? 80 : 60`
  with contents inset 30 (34 in selection mode). Measured against the conversation pane's
  avatar, both now centre 32px below the window's top edge; the list avatar was 9.5px lower.
- `e7e174b83` — the chat `ListView` carried an 8px top padding inside a body already clipped
  to a 26px top radius, so the rounding never drew and the padding read as a dead band under
  the header. Measured 10px of background before, 0 after.
- `3dfb7c206` — the Material conversation tile rounded only its left corners, leaving the
  highlight square where it meets the split-view divider. `cupertino_conversation_tile.dart:107`
  and `pinned_conversation_tile.dart:93` both already round all four. The file's four radius
  sites were also three different values (25/20/20/20); they are now one.

### Documentation

- `docs/MESSAGE_RECEIVE_FLOW.md` — the typing indicator's settle time was documented as
  ~480ms (280ms scale then 200ms collapse); the scale is now 200ms, so it is ~400ms.

### Decisions

- **Material is the better base skin than iOS for the Linux desktop client.** It is the only
  skin with a design-token layer (`lib/app/components/m3e/`). iOS is the default
  (`settings.dart:184`) and the largest (17 files / 5,341 lines vs 15 / 3,564) but is
  touch-first. Samsung is a veneer: 12 files / 2,303 lines, 9 `kIsDesktop` mentions against
  19 and 18, last touched 2026-08-10.
- **Adopt M3E motion; do not adopt M3E shapes or spacing.** There is no house motion system,
  which is why `Cubic(0.23, 1.0, 0.32, 1.0)` was hand-written 19 times — `M3EMotion.spatialFast`
  is 200ms + `emphasizedDecelerate`, the same value chosen by ear. But the house radius is 20
  (59 of ~130 radii in the conversation surfaces), which falls between `M3EShapes.lg` 16 and
  `xl` 28; and the house spacing grid is 5px (10: 87 hits, 5: 55, 15: 39, 20: 23) against
  M3E's 4px scale, where only `8` and `0` overlap. Shape and spacing already have a
  consistent house language that simply is not Material's.
