import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';

Future<void> setChatSpamVerdict(Chat chat, String verdict) async {
  try {
    final response = await HttpSvc.chat.setSpamVerdict(chat.guid, verdict);
    final updated = Chat.findOne(guid: chat.guid) ?? chat;
    updated.spamVerdict = response.data['data']['spamVerdict'] as String?;
    final saved = await updated.saveAsync(updateSpamVerdict: true);
    ChatsSvc.updateChat(saved, override: true);
  } catch (error, stack) {
    Logger.error('Failed to update spam verdict for ${chat.guid}', error: error, trace: stack);
    showSnackbar('Error', "Couldn't update spam status for ${chat.getTitle()}", type: SnackbarType.error);
  }
}
