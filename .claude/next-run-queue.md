# Units queued for the next autonomous run

Each entry was approved by James for a future run; they are not done. Take them from the top. Remove an entry in
the same commit that lands it.

## Drafts store who was mentioned, not their position in the participant list

Queued 2026-09-28, as the follow-up to U139 (`autonomous/r0927-stale-mention-index`, merged into
`autonomous/combined-2026-09-27`).

**Defect.** A mention in the composer is a marker holding the person's index into
`ConversationViewController.mentionables` (`lib/services/ui/chat/conversation_view_controller.dart:101`, built from
`chat.handles`). The draft is saved with that marker as-is (`conversation_text_field.dart:167` debounced save and
`:319` on dispose) and restored as-is (`getTextDraft`, `:115`). If the chat's participants change between save and
restore, the index points at no one, and U139 now renders that as plain text instead of crashing. Or it points at a
different person, and the restored draft silently tags the wrong participant. Nothing warns the user.

**Fix.** On save, write each marker as the mentioned handle's address. On restore, map the address back to its current
index in `mentionables`. If the person is no longer a participant, restore their display name as plain text. The
marker format and parsing live in `MentionTextEditingController` (`lib/app/components/custom_text_editing_controllers.dart`,
`escapingChar`). Drafts saved in the old index format already exist on devices, so restore must still read them:
treat an index-only marker as today's U139 behaviour.

**Acceptance.** Save a draft with a mention in a group chat, then change the participants (remove the mentioned person,
or remove someone listed before them), then reopen the chat. The mention either stays attached to the same person or
becomes that person's name as plain text. It never tags anyone else. Old drafts still restore.

**Verify.** `flutter analyze --no-pub --no-fatal-infos` (no new issues) and `flutter build linux --debug --no-pub`, then
a manual check in a group chat on a live server.
