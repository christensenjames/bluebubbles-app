# app/layouts/fullscreen_media/ — Full-Screen Media Viewer

## Files
| File | Purpose |
|------|---------|
| `conversation_fullscreen_holder.dart` | Gallery holder for a chat's attachments — pinch-zoom, `PageView` paging, reply-to-attachment, keyboard arrow navigation |
| `single_attachment_fullscreen_viewer.dart` | Single-item holder for one local/unsent attachment — no paging, reply, or gallery state |
| `fullscreen_image.dart` | Full-screen image viewer |
| `fullscreen_video.dart` | Full-screen video player |

## Usage

**`ConversationFullscreenHolder`** — use when viewing an attachment that belongs to a chat/message (in-bubble tap, gallery card), where paging through the chat's other attachments and replying to a specific attachment matter:
```dart
Navigator.push(context, MaterialPageRoute(
  builder: (_) => ConversationFullscreenHolder(attachment: attachment, showInteractions: true),
));
```

**`SingleAttachmentFullscreenViewer`** — use when previewing one local, not-yet-sent `PlatformFile`/`Attachment` (e.g. the composer's picked-attachment preview), where there's no chat context, gallery, or reply target:
```dart
SingleAttachmentFullscreenViewer(file: file, attachment: attachment, showInteractions: false);
```

Both dispatch on the attachment's mime type and render `FullscreenImage` or `FullscreenVideo` as the child, and both drive a "Done"/close button off the child's `onOverlayToggle` callback — `ConversationFullscreenHolder` tracks it against a paged attachment list, `SingleAttachmentFullscreenViewer` tracks it directly with no intermediate state.

## Key Behaviors
- Pinch-to-zoom (in `ConversationFullscreenHolder`) and standard image gestures — child widgets do not need to implement it themselves
- Tap to toggle the overlay/system UI (hide/show status bar, navigation, and action bars) — handled inside `FullscreenImage`/`FullscreenVideo`, independent of `showInteractions`
- `showInteractions` gates which action buttons are relevant (download/reply/share/etc.), not whether the overlay can be shown/hidden
- `FullscreenVideo` disposes only a player it created; a player borrowed from the inline chat video (`videoController`) is handed back with speed and loop reset
- `FullscreenVideo` puts its actions (close, info, re-download, save, share, PiP, speed, loop, mute) inside media_kit's control overlay; `FullscreenImage` keeps its own action bar for shares/saves
- Material skin only: `ConversationFullscreenHolder` draws one shared `ViewerChrome` (`viewer_chrome.dart`) over every page and owns its visibility and the system-UI mode; pages are built with `onTap`/`sharedChrome` and draw no bars of their own. `FullscreenImage` zooms with `ZoomableMedia` (swipe-down dismiss, `Hero` from the chat bubble through `ThemeSwitcher.buildTransparentPageRoute`) and leaves `PageView` paging unlocked. iOS/Samsung keep PhotoView, per-page bars, and the paging lock. `SingleAttachmentFullscreenViewer` passes neither flag, so its pages keep their own close bar.

## Related
- Attachment models: `lib/database/io/attachment.dart`
- Attachment download state: `lib/services/ui/attachments_service.dart`
- Thumbnails in the chat: `lib/app/layouts/conversation_view/widgets/message/attachment/`
- Composer preview: `lib/app/layouts/conversation_view/widgets/text_field/picked_attachment.dart`
