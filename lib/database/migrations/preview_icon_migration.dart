import 'dart:convert';

import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';

class PreviewIconMigration {
  static Set<String> hashes() {
    final query = Database.messages.query(Message_.dbMetadata.contains('previewIconMd5')).build();
    final metadata = query.property(Message_.dbMetadata).find();
    query.close();
    return hashesFromMetadata(metadata);
  }

  static Set<String> hashesFromMetadata(Iterable<String> metadata) {
    final hashes = <String>{};
    for (final json in metadata) {
      try {
        final decoded = jsonDecode(json);
        if (decoded is Map && decoded['previewIconMd5'] is String) {
          hashes.add(decoded['previewIconMd5'] as String);
        }
      } on FormatException {
        continue;
      }
    }
    return hashes;
  }
}
