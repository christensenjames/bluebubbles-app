# conversation_view/widgets/header/ — Conversation Header Bar

Three files. The header follows the standard skin pattern — each skin has its own implementation sharing the same controller.

## Files
| File | Contents |
|------|---------|
| `cupertino_header.dart` | iOS-skin header (title, back button, avatar, call button) |
| `material_header.dart` | Material-skin header |
| `header_widgets.dart` | Shared sub-widgets used across skins — `ManualMark` (private API read receipt button), connection status indicator, and other reusable pieces |

## Skin Pattern

The parent `ConversationView` page selects `CupertinoHeader` for the iOS skin and `MaterialHeader` otherwise. Both receive the same `ConversationViewController`. Header state (chat title, avatar, typing indicator) is read from the controller or directly from `ChatState`.

## Shared Widgets (`header_widgets.dart`)

**`ManualMark`** — lets the user manually mark the chat as read on the server when Private API and `privateManualMarkAsRead` are enabled and the chat does not automatically send read receipts.

When adding new header features, add shared logic or sub-widgets to `header_widgets.dart` and reference them from the skin-specific files rather than duplicating.

## Related
- Controller: `lib/services/ui/chat/conversation_view_controller.dart`
- Chat reactive state: `lib/app/state/chat_state.dart`
- Parent page: `lib/app/layouts/conversation_view/pages/conversation_view.dart`
