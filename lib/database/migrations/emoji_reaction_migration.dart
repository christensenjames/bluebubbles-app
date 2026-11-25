import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/ui/reaction_helpers.dart';

class EmojiReactionMigration {
  static void migrate() {
    Database.runInTransaction(TxMode.write, () {
      final query = Database.messages.query(
        Message_.associatedMessageType.oneOf(['emoji', '-emoji']),
      ).build();
      final messages = query.find();
      query.close();
      for (final message in messages) {
        message.associatedMessageType = message.associatedMessageType == 'emoji'
            ? ReactionTypes.EMOJI
            : ReactionTypes.REMOVED_EMOJI;
      }
      Database.messages.putMany(messages);
    });
  }
}
