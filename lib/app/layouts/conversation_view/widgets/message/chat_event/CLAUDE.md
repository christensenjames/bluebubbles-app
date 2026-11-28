# widgets/message/chat_event/ — System / Chat Event Messages

## Files
| File | Purpose |
|------|---------|
| `chat_event.dart` | Renders system-generated chat event rows (member added/removed, name changed, group photo changed, video/audio call started, etc.) |

## Usage
Rendered instead of a normal message bubble when `message.isGroupEvent || part.isUnsent`.

## Styling
Centered, muted text without a bubble tail. Uses `context.theme.textTheme.bodySmall` with reduced opacity.

## Related
- Message routing: `../message_holder.dart` (decides chat_event vs normal bubble)
- DB model: `lib/database/io/message.dart` — `itemType`, `groupActionType`, `groupTitle`
