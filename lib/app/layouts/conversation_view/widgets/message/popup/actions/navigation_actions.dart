import 'dart:io';
import 'dart:typed_data';

import 'package:bluebubbles/app/layouts/chat_creator/chat_creator.dart';
import 'package:bluebubbles/app/layouts/chat_creator/new_chat_creator.dart';
import 'package:bluebubbles/app/layouts/conversation_view/pages/conversation_view.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/message_popup_action_context.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/reply/reply_thread_popup.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/models/models.dart' show MessageReplyContext;
import 'package:collection/collection.dart';
import 'package:flutter/widgets.dart';

void reply(MessagePopupActionContext ctx) {
  ctx.popDetails();
  ctx.cvController.replyToMessage = MessageReplyContext(ctx.message, ctx.part.part);
}

void openDm(MessagePopupActionContext ctx) {
  if (ctx.dmChat == null) return;
  ctx.popDetails();
  Navigator.pushReplacement(
    ctx.context,
    ThemeSwitcher.buildPageRoute(builder: (BuildContext context) => ConversationView(chat: ctx.dmChat!)),
  );
}

void showThread(MessagePopupActionContext ctx) {
  ctx.popDetails();
  if (ctx.message.threadOriginatorGuid != null) {
    final mwc = ctx.service.getMessageStateIfExists(ctx.message.threadOriginatorGuid!);
    if (mwc == null) return ctx.showSnack("Error", "Failed to find thread!", type: SnackbarType.error);
    final part = mwc.parts.firstWhereOrNull((p) => p.part == ctx.message.normalizedThreadPart);
    if (part == null) return ctx.showSnack("Error", "Failed to find thread!", type: SnackbarType.error);
    showReplyThread(ctx.context, mwc.message, part, ctx.service, ctx.cvController);
  } else {
    showReplyThread(ctx.context, ctx.message, ctx.part, ctx.service, ctx.cvController);
  }
}

void newConvo(MessagePopupActionContext ctx) {
  final Handle? handle = ctx.message.handleRelation.target;
  if (handle == null) return;
  ctx.popDetails();
  // This route replacement bypasses ConversationView's back-handler, so
  // explicitly close the active controller first.
  ctx.cvController.close();
  NavigationSvc.pushAndRemoveUntil(
    ctx.context,
    NewChatCreator(initialSelected: [SelectedContact(displayName: handle.displayName, address: handle.address)]),
    (route) => route.isFirst,
  );
}

Future<void> forward(MessagePopupActionContext ctx) async {
  final navigator = Navigator.of(ctx.context);
  ctx.popDetails();
  final List<PlatformFile> attachments = [];
  final _attachments = ctx.part.attachments
      .where((e) => AttachmentsSvc.getContent(e, autoDownload: false) is PlatformFile)
      .map((e) => AttachmentsSvc.getContent(e, autoDownload: false) as PlatformFile);
  for (final PlatformFile a in _attachments) {
    Uint8List? bytes = a.bytes;
    bytes ??= await File(a.path!).readAsBytes();
    attachments.add(PlatformFile(
      name: a.name,
      path: a.path,
      size: bytes.length,
      bytes: bytes,
    ));
  }

  if (!navigator.mounted) return;
  if (attachments.isNotEmpty || !isNullOrEmpty(ctx.part.text)) {
    // This route replacement bypasses ConversationView's back-handler, so
    // explicitly close the active controller first.
    ctx.cvController.close();
    NavigationSvc.pushAndRemoveUntil(
      navigator.context,
      NewChatCreator(
        initialText: ctx.part.text,
        initialAttachments: attachments,
      ),
      (route) => route.isFirst,
    );
  } else {
    ctx.showSnack("Forward Error", "Download the attachment before forwarding it.");
  }
}
