import 'dart:async';

import 'package:bluebubbles/app/layouts/chat_creator/new_chat_creator.dart';
import 'package:bluebubbles/app/layouts/settings/pages/scheduling/scheduled_messages_panel.dart';
import 'package:bluebubbles/app/layouts/settings/pages/server/server_management_panel.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/helpers/backend/startup_tasks.dart';
import 'package:bluebubbles/helpers/ui/facetime_helpers.dart';

import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/chat_creator/chat_creator.dart';
import 'package:bluebubbles/app/layouts/conversation_view/pages/conversation_view.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide Intent;
import 'package:get/get.dart';
import 'package:bluebubbles/models/models.dart' show HandleLookupKey;
import 'package:path/path.dart';
import 'package:receive_intent/receive_intent.dart';
import 'package:universal_io/io.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:get_it/get_it.dart';

// ignore: non_constant_identifier_names
IntentsService get IntentsSvc => GetIt.I<IntentsService>();

class IntentsService {
  late final StreamSubscription sub;

  /// When a notification tap triggers navigation to a specific chat, this is
  /// set synchronously (before any async gap) so that [onAppResume] can skip
  /// marking the previously-active chat as read while the redirect is pending.
  String? pendingOpenChatGuid;

  Future<void> init() async {
    if (kIsWeb || kIsDesktop) return;

    // getInitialIntent() reflects Activity.getIntent() at attach time, which fires
    // on every new/recreated Activity — including cases where the OS destroyed the
    // Activity but the Dart isolate (and ChatsSvc.activeChat) survived underneath
    // (e.g. via the foreground-service keep-alive). The widget tree is starting
    // fresh either way, so activeChat can't be trusted for the "already open"
    // shortcut on this path. receivedIntentStream, by contrast, only fires for an
    // Activity that was already attached and running, where activeChat is
    // guaranteed to be in sync with what's on screen.
    final intent = await ReceiveIntent.getInitialIntent();
    handleIntent(intent, isInitialIntent: true);

    sub = ReceiveIntent.receivedIntentStream.listen((Intent? intent) {
      handleIntent(intent, isInitialIntent: false);
    }, onError: (err) {
      Logger.error("Failed to get intent!", error: err);
    });
  }

  void close() async {
    await sub.cancel();
  }

  void handleIntent(Intent? intent, {required bool isInitialIntent}) async {
    if (intent == null) return;

    // Every activity launch tells us whether we're running as a bubble. Set it
    // for ALL intents, not just chat-opens — otherwise isBubble stays true after
    // a bubble session when the app is next opened from the launcher or a share
    // sheet, misrouting lifecycle teardown to closeBubble() indefinitely.
    LifecycleSvc.isBubble = intent.extra?["bubble"] == true;

    switch (intent.action) {
      case "android.intent.action.SEND":
      case "android.intent.action.SEND_MULTIPLE":
        final id = intent.extra?["android.intent.extra.shortcut.ID"];
        final text = intent.extra?["android.intent.extra.TEXT"];
        final files = <PlatformFile>[];
        int failed = 0;
        if (intent.extra?["android.intent.extra.STREAM"] != null) {
          final data = intent.extra!["android.intent.extra.STREAM"];
          final uris = data is List ? data : [data.toString()];
          for (final uri in uris) {
            if (uri is! String) {
              Logger.warn("Unreadable shared STREAM entry $uri", tag: "IntentsService");
              failed++;
              continue;
            }
            try {
              final path = await MethodChannelSvc.actions.getContentUriPath(uri: uri);
              if (path == null) {
                Logger.warn("Could not resolve path for shared URI $uri", tag: "IntentsService");
                failed++;
                continue;
              }
              final bytes = await File(path).readAsBytes();
              files.add(PlatformFile(
                path: path,
                name: basename(path),
                bytes: bytes,
                size: bytes.length,
              ));
            } catch (e, s) {
              Logger.warn("Failed to read shared URI $uri", tag: "IntentsService", error: e, trace: s);
              failed++;
            }
          }
        }
        if (failed > 0) {
          // Not awaited: showSnackbar needs the UI, and openChat's push may not complete until the route is popped.
          StartupTasks.waitForUI().then((_) => showSnackbar("Error", "Failed to load $failed shared file(s)!"));
        }
        await openChat(id, text: text, attachments: files, isInitialIntent: isInitialIntent);
        return;
      default:
        if (intent.data?.startsWith("imessage://") ?? false) {
          if (!SettingsSvc.settings.finishedSetup.value) return;
          final uri =
              Uri.tryParse(intent.data!.replaceFirst("imessage://", "imessage:").replaceFirst("&body=", "?body="));
          if (uri != null) {
            await StartupTasks.waitForUI();
            final address = uri.path;
            final handle = Handle.findOne(addressAndService: HandleLookupKey(address, "iMessage"));
            NavigationSvc.pushAndRemoveUntil(
              Get.context!,
              NewChatCreator(
                initialSelected: [SelectedContact(displayName: handle?.displayName ?? address, address: address)],
                initialText: uri.queryParameters['body'],
              ),
              (route) => route.isFirst,
            );
          }
        } else if (intent.extra?["chatGuid"] != null) {
          final guid = intent.extra!["chatGuid"]!;
          await openChat(guid, isInitialIntent: isInitialIntent);
        } else if (intent.extra?["callUuid"] != null) {
          await StartupTasks.waitForUI();
          if (intent.extra?["answer"] == true) {
            await answerFaceTime(intent.extra?["callUuid"]!);
          } else {
            await showFaceTimeOverlay(intent.extra?["callUuid"], intent.extra?["caller"], null, false);
          }
        }
    }
  }

  Future<void> answerFaceTime(String callUuid) async {
    DialogRoute? route;
    if (Get.context != null) {
      final nav = Navigator.of(Get.context!, rootNavigator: true);
      route = DialogRoute(
          context: Get.context!,
          barrierColor: Get.context!.theme.dialogTheme.barrierColor ?? Colors.black54,
          traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
          builder: (BuildContext context) {
            return AlertDialog(
              backgroundColor: context.theme.colorScheme.surfaceContainerHighest,
              title: Text(
                "Generating link for call...",
                style: context.theme.textTheme.titleLarge,
              ),
              content: SizedBox(
                height: 70,
                child: Center(
                  child: CircularProgressIndicator(
                    backgroundColor: context.theme.colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(context.theme.colorScheme.primary),
                  ),
                ),
              ),
            );
          });
      nav.push(route);
      hideFaceTimeOverlay(callUuid);
    }

    String? link;
    try {
      final call = await HttpSvc.faceTime.answer(callUuid);
      link = call.data?["data"]?["link"];
    } catch (e, s) {
      Logger.warn("Failed to fetch FaceTime answer link", error: e, trace: s, tag: 'IntentsService');
    }
    if (route != null) NavigationSvc.closeRoute(route);
    if (link == null) {
      return showSnackbar("Failed to answer FaceTime", "Unable to generate FaceTime link!");
    }

    if (!kIsWeb) {
      await launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication);
    } else if (kIsWeb) {
      // TODO: Implement web FaceTime
    }
  }

  Future<void> openChat(String? guid,
      {String? text, List<PlatformFile> attachments = const [], required bool isInitialIntent}) async {
    Logger.info("Handling open chat intent with guid: $guid", tag: "IntentsService");

    if (guid == null) {
      Logger.debug("Opening new chat creator..", tag: "IntentsService");
      await StartupTasks.waitForUI();
      NavigationSvc.pushAndRemoveUntil(
        Get.context!,
        NewChatCreator(
          initialAttachments: attachments,
          initialText: text,
        ),
        (route) => route.isFirst,
      );
    } else if (guid == "-1") {
      Logger.debug("Popping all routes...", tag: "IntentsService");
      if (ChatsSvc.activeChat != null) {
        Navigator.of(Get.context!).popUntil((route) => route.isFirst);
      }
    } else if (guid == "-2") {
      Logger.debug("Opening server management panel...", tag: "IntentsService");
      Navigator.of(Get.context!).push(
        ThemeSwitcher.buildPageRoute(
          builder: (BuildContext context) {
            return ServerManagementPanel();
          },
        ),
      );
    } else if (guid.contains("scheduled")) {
      Logger.debug("Opening scheduled messages panel...", tag: "IntentsService");
      Navigator.of(Get.context!).push(
        ThemeSwitcher.buildPageRoute(
          builder: (BuildContext context) {
            return const ScheduledMessagesPanel();
          },
        ),
      );
    } else {
      Logger.debug("Opening existing chat (Attachments: ${attachments.length}; Text: ${text?.shorten(10) ?? 'N/A'})",
          tag: "IntentsService");
      final chat = Chat.findOne(guid: guid);
      if (chat == null) {
        Logger.debug("Chat not found with guid: $guid", tag: "IntentsService");
        return;
      }

      // Must precede the first await: onAppResume can run while we're suspended and reads this.
      pendingOpenChatGuid = guid;
      await StartupTasks.waitForUI();

      // On the initial-intent path the widget tree is starting fresh (see the
      // comment in init()), so activeChat may be a stale leftover from before the
      // Activity was torn down — always navigate explicitly in that case rather
      // than trusting it to already reflect what's on screen.
      bool chatIsOpen = !isInitialIntent && ChatsSvc.activeChat?.chat.guid == guid;
      Logger.debug("Chat is active: $chatIsOpen", tag: "IntentsService");

      setPickedAttachments() {
        if (attachments.isNotEmpty) {
          cvc(chat).pickedAttachments.value = attachments;
        }

        if (text != null && text.isNotEmpty) {
          cvc(chat).textController.text = text;
        }
      }

      // A newer openChat may have replaced the guid while this one was suspended.
      clearPendingOpenChat() {
        if (pendingOpenChatGuid == guid) pendingOpenChatGuid = null;
      }

      if (!chatIsOpen) {
        Logger.debug("Navigating to conversation view...", tag: "IntentsService");

        // Rather than waiting for paging to eventually reach this chat,
        // proactively seed its ChatState now. getOrCreateChatState() inserts
        // a fully valid ChatState immediately and is a no-op if the batch
        // loader already added it.
        ChatsSvc.getOrCreateChatState(chat);

        // Pre-populate text/attachments on the controller before navigating so
        // the ConversationView text field is pre-filled on first build.
        setPickedAttachments();

        // Clear once ConversationView makes this chat active; clearing on route pop would skip chats pushed on top.
        WidgetsBinding.instance.addPostFrameCallback((_) => clearPendingOpenChat());
        await NavigationSvc.pushAndRemoveUntil(
          Get.context!,
          ConversationView(chat: chat),
          (route) => route.isFirst,
        );
      } else {
        clearPendingOpenChat();
        Logger.debug("Chat is already open, not navigating", tag: "IntentsService");
        setPickedAttachments();
      }
    }
  }
}
