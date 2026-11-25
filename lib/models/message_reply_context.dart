import 'package:flutter/foundation.dart';
import 'package:bluebubbles/database/models.dart';

@immutable
class MessageReplyContext {
  final Message message;

  /// Message-part id being replied to
  final int partIndex;

  /// When set, scopes the reply to a specific attachment within [partIndex].
  final String? attachmentGuid;

  final DateTime pickedAt;

  MessageReplyContext(this.message, this.partIndex, {this.attachmentGuid, DateTime? pickedAt})
      : pickedAt = pickedAt ?? DateTime.now();
}
