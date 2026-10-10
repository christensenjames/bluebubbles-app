# Services Rules — Service Layer, Events & Platform Bridges

## Service Registration & Access

Services use two service locators. Services registered in `lib/helpers/backend/startup_tasks.dart` use GetIt; classes extending `GetxService` use GetX. Service shortcuts are top-level getters in their individual service files; `lib/services/services.dart` only re-exports those files.

**Registration and access pattern:**
```dart
// Registered in startup_tasks.dart
GetIt.I.registerSingleton<ChatsService>(ChatsService());

// Shortcut declared in chats_service.dart
ChatsSvc.init();

// Direct GetIt access
final settingsService = GetIt.I<SettingsService>();
```

To choose the locator, check whether the service is registered in `startup_tasks.dart` or its class extends `GetxService`. New services should follow the GetIt registration path. Use the existing service shortcut when one exists; otherwise access GetIt services with `GetIt.I<T>()` and GetX services with their existing GetX access pattern.

## Event Dispatch (Backend → UI)

`EventDispatcherSvc.stream` is a broadcast stream of `DispatchedEvent` objects with `.type` and `.data` fields.

**Emitting:**
```dart
EventDispatcherSvc.emit('chat-updated', chat.guid);
```

**Listening (in `initState`):**
```dart
EventDispatcherSvc.stream.listen((event) {
  if (event.type == 'chat-updated' && mounted) {
    final guid = event.data as String;
    // handle update
  }
});
```

- Use named string event types — document new event types near the emit site.
- Always check `mounted` before calling `setState()` in a listener.
- Cancel stream subscriptions in `dispose()`.

## Background Processing

- `runAsync` defers a synchronous callback through `SchedulerBinding` on the main isolate at animation priority; it is not off-thread work. Use `GlobalIsolate` through `IsolateRequestType` for heavy operations.
- Cross-isolate communication goes through `GlobalIsolate` via `IsolateRequestType` — don't spawn raw `Isolate.spawn`.
- `background_isolate.dart` (Android) handles Dart work triggered by platform background tasks.

## Method Channels (Android Bridge)

```dart
await MethodChannelSvc.invokeMethod('method-name', {
  'key': value,
});
```

- Method names use kebab-case strings matching the Kotlin handler.
- Corresponding Kotlin code lives in `android/app/src/main/kotlin/.../services/`.
- Always guard method channel calls behind `!kIsWeb && !kIsDesktop` where appropriate.
- New method channels need handlers on both sides: Dart (`method_channel_service.dart`) and Kotlin (`MainActivity.kt` or a dedicated service).

## Settings Access

```dart
// Read
SettingsSvc.settings.someFlag.value

// Write (triggers reactive update)
SettingsSvc.settings.someFlag.value = newValue;
await SettingsSvc.saveSettings();
```

New settings fields are defined in `lib/database/global/settings.dart` (see `database.md`).

## Navigation

```dart
NavigationSvc.push(context, MyWidget());
NavigationSvc.pushAndRemoveUntil(context, MyWidget());
NavigationSvc.pop(context);
```

Use `NavigationSvc` — don't call `Navigator.of(context)` directly in feature code.

## Contacts

- V1 (legacy): `ContactsSvc` — returns `Contact` objects
- V2 (current): `ContactsSvcV2` — returns `ContactV2` objects
- Prefer V2 for any new feature work. Check `ContactsSvcV2.isHandleUpdated(handle.id)` in `ever()` listeners for reactive contact updates.
