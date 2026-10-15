import 'package:bluebubbles/app/components/custom_text_editing_controllers.dart';
import 'package:bluebubbles/app/layouts/conversation_details/dialogs/timeframe_picker.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/effects/send_effect_picker.dart';
import 'package:bluebubbles/database/global/platform_file.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:universal_io/io.dart';

Future<void> scheduleMessage(BuildContext context, ConversationViewController controller) async {
  if (controller.pickedAttachments.isNotEmpty) {
    return showSnackbar("Error", "Remove all attachments before scheduling!", type: SnackbarType.error);
  } else if (controller.replyToMessage != null || controller.subjectTextController.text.isNotEmpty) {
    return showSnackbar("Error", "Private API features are not supported when scheduling!", type: SnackbarType.error);
  }

  final date = await showTimeframePicker("Pick date and time", context, presetsAhead: true);
  if (date != null && date.isAfter(DateTime.now())) {
    controller.scheduledDate.value = date;
  }
}

Future<void> pickImagesIntoAttachments(ConversationViewController controller) async {
  final List<String> paths = await MethodChannelSvc.actions.pickImages();
  for (final path in paths) {
    final file = File(path);
    final size = await file.length();
    if (size / 1024000 > 1000) {
      showSnackbar("Error", "This file is over 1 GB! Please compress it before sending.", type: SnackbarType.error);
      continue;
    }
    controller.pickedAttachments.add(PlatformFile(
      path: file.path,
      name: file.path.split('/').last,
      size: size,
      bytes: null,
    ));
  }
}

void sendTextFieldEffects(
  BuildContext context,
  ConversationViewController controller,
  String text,
  String subjectText,
  Future<void> Function({String? effect}) sendMessage,
  List<Mentionable> mentionables,
) {
  if (controller.scheduledDate.value != null) {
    showSnackbar("Error", "Private API features are not supported when scheduling!", type: SnackbarType.error);
    return;
  }
  sendEffectAction(
    context,
    controller,
    text,
    subjectText,
    controller.replyToMessage?.message.guid,
    controller.replyToMessage?.partIndex,
    controller.chat.guid,
    sendMessage,
    mentionables,
  );
}
