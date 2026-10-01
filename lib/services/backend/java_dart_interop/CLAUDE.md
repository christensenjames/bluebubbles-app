# services/backend/java_dart_interop/ — Dart ↔ Android Bridge

These files form the Dart side of the Android method channel bridge. The Kotlin side lives in `android/app/src/main/kotlin/com/bluebubbles/messaging/`.

For the full Android bridge overview, see `android/CLAUDE.md`.

## Files

### `method_channel_service.dart` — `MethodChannelService` / `MethodChannelSvc`

GetIt singleton. The primary bridge between Dart and Android. Uses `MethodChannel('com.bluebubbles.messaging')`.

**Calling Android from Dart:**
```dart
await MethodChannelSvc.invokeMethod("method-name", {"key": "value"});
```

Key methods invoked:
- `"push-notify"` — trigger a local notification
- `"delete-notification"` — clear a notification by ID
- `"start-foreground"` / `"stop-foreground"` — foreground service control
- `"get-server-url"` — read server URL from Android SharedPreferences

**Android calling Dart:** The service also registers a `MethodCallHandler` to receive calls from Kotlin (e.g. handling an incoming notification tap, background wake-up).

**Guards:** Initialization is skipped in headless/bubble/desktop modes. Always check `MethodChannelSvc.isAvailable` before calling on non-Android platforms.

---

### `pip_service.dart` — `PipService` / `PipSvc`

GetIt singleton for picture-in-picture support and playback state.

**Calling Android from Dart:**
- `"pip-supported"` — query support, returning a Boolean
- `"pip-enter"` — enter PiP with `{"aspectRatio": double}`, returning null
- `"pip-auto-enter"` — configure auto-enter with `{"enabled": bool, "aspectRatio": double?}`, returning null; omit `aspectRatio` when absent

**Android calling Dart:**
- `"pip-mode-changed"` — `{active: bool}`, exposed as `PipSvc.active`
- `"pip-dismissed"` — `{}`, exposed as `PipSvc.dismissed`

---

### `intents_service.dart` — `IntentsService`

Handles Android intents arriving at the Flutter layer (share targets, notification deep links, app shortcuts).

Listens to `ReceiveIntent.receivedIntentStream` and routes by action:
- Share intent → pre-fill the chat composer with shared content
- Notification tap → open the correct conversation
- Custom deep link → navigate to the specified screen

---

### `background_isolate.dart`

Minimal setup for the Android background isolate (used when the app is killed but a Firebase push arrives). Stores a callback handle to `SharedPreferences` and defines the `@pragma('vm:entry-point')` entry point that initializes HTTP overrides and calls `StartupTasks.initBackgroundIsolate()`.

This is distinct from `GlobalIsolate` (see `lib/services/isolates/CLAUDE.md`) — it's the Android-specific background execution path, not the in-process Dart isolate used for DB operations.
