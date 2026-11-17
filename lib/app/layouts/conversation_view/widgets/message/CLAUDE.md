# widgets/message/ — Message Rendering (54+ files)

A message renders as a composition of specialized sub-widgets.

## Component Routing
| Directory | Renders | Details |
|-----------|---------|---------|
| `message_holder/` | Outer bubble, alignment, tail, sender name | → CLAUDE.md inside |
| `text/` | Text content inside bubble | |
| `attachment/` | Images, video, audio, stickers, contact cards | → CLAUDE.md inside |
| `reaction/` | Tapback emoji display and picker | → CLAUDE.md inside |
| `reply/` | Quoted reply bubble and reply line | → CLAUDE.md inside |
| `timestamp/` | Delivery status, read receipts, date separators | → CLAUDE.md inside |
| `typing/` | Typing indicator | |
| `popup/` | Long-press context menu / action sheet | → CLAUDE.md inside |
| `interactive/` | Apple Pay, Game Pigeon, URL previews, maps, embedded media | → CLAUDE.md inside |
| `chat_event/` | System messages (member added, subject changed) | |
| `misc/` | Message editing, selection, swipe-to-reply dispatcher, bubble effect overlay (`bubble_effects.dart`) | → CLAUDE.md inside |
| `shared/` | Shared utilities across message widgets | |

## Message Clones

`MessagePopup` re-renders the bubble it was opened from against the **same** `MessageState`, so
while the popup is open there are two complete copies of every widget in that message — each with
its own state and its own listeners on the shared observables. Anything that reacts to a shared
signal by *doing work* (rather than just drawing) must check
`MessageCloneScope.of(context)` in `initState` and skip subscribing, or the work runs twice.
`previewRefreshKey` is the case this was built for: "Refresh Preview" is dispatched before the
popup closes, so both listeners fire.

See `shared/message_clone_scope.dart`.

## Accessibility

`_MessageSemantics` orders the sender and bubble before a separate time/delivery node.
The trailing node fills the message bounds and sits beneath the content, so touch
exploration still lands on the bubble; a zero-size node would be dropped from
accessibility traversal. Keep links, attachments,
and the error button as independent descendants rather than merging the subtree.
`MessagePopupHolder` registers secondary taps only on desktop/web, because even a
secondary-only tap recognizer contributes a semantics tap action.

## Related
- Reactive state: `lib/app/state/message_state.dart`
- DB model: `lib/database/io/message.dart`
- Animations: `lib/app/animations/`
- Full-screen send effect overlay + picker (balloon, confetti, etc.): sibling directory `conversation_view/widgets/effects/` → `CLAUDE.md` inside
- Popup action handlers: `popup/actions/` (menu behavior extracted from `popup/message_popup.dart`)
