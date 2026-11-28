# services/backend/filesystem/ — File System Service

## File
`filesystem_service.dart` — `FilesystemService` (registered with GetIt via `FilesystemSvc` shorthand)

## Responsibilities
- Resolves platform-specific paths for attachments, cache, and temp files
- Manages attachment download destinations (per-GUID subdirectories)
- Cleans up orphaned/cached files when attachments are deleted
- Copies, moves, and deletes files as part of the attachment pipeline

## Key Methods
- `downloadsDirectory` → platform downloads directory (async getter)
- `saveToDownloads(File, {mimeType})` → saves a file to the platform Downloads folder
- `saveUrlPreviewImage(Uint8List)` → writes a URL preview image, returns its path
- `chatAvatarPath(chatGuid)` → per-chat avatar file path
- `deleteCacheDirectories({keepUserAvatar})` → clears attachment, avatar, background, message and URL preview caches

## Related
- Attachment actions: `lib/services/backend/actions/attachment_actions.dart`
- Download manager: `lib/services/network/downloads_service.dart`
