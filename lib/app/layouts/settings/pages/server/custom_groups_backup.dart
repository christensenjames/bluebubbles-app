import 'package:bluebubbles/app/layouts/settings/pages/server/chat_backup_identifier.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/backend/interfaces/custom_group_interface.dart';
import 'package:bluebubbles/services/services.dart';

/// Result of restoring a `customGroups` backup entry list.
class CustomGroupsRestoreResult {
  final List<String> restored;
  final List<String> skipped;

  const CustomGroupsRestoreResult({required this.restored, required this.skipped});
}

/// Exports/imports custom groups in a server/device-agnostic way for the
/// Settings backup/restore feature. Member chats are identified via
/// [ChatBackupIdentifier] rather than `chat.guid`. Group names are unique
/// locally, so on restore a group whose name already exists has the backup's
/// members merged into it (union) instead of being duplicated.
class CustomGroupsBackup {
  static Future<List<Map<String, dynamic>>> exportList() async {
    final groups = await CustomGroupInterface.getAll();
    return groups.map((g) {
      return {
        "name": g.name,
        "chats": g.chats.map(ChatBackupIdentifier.export).toList(),
        "showUnreadBadge": g.showUnreadBadge,
      };
    }).toList();
  }

  static Future<CustomGroupsRestoreResult> restore(List<dynamic> entries) async {
    final restored = <String>[];
    final skipped = <String>[];

    final existing = {for (final g in await CustomGroupInterface.getAll()) g.name: g};

    for (final entry in List<Map<String, dynamic>>.from(entries)) {
      final baseName = entry["name"] as String;
      final chatEntries = List<Map<String, dynamic>>.from(entry["chats"] as List? ?? []);

      final matchedGuids = <String>[];
      for (final chatEntry in chatEntries) {
        final result = ChatBackupIdentifier.resolve(chatEntry, ChatsSvc.allChats);
        if (result.match != null) {
          matchedGuids.add(result.match!.guid);
        } else {
          final displayName = chatEntry["displayName"] as String?;
          final participants = List<String>.from(chatEntry["participants"] as List? ?? []);
          final label = !isNullOrEmpty(displayName) ? displayName! : participants.join(", ");
          skipped.add("$baseName: $label (${result.skipReason})");
        }
      }

      var group = existing[baseName];
      if (group != null) {
        final current = group.chats.map((c) => c.guid).toSet();
        if (!current.containsAll(matchedGuids)) {
          group = await CustomGroupInterface.updateChats(
              id: group.id!, chatGuids: {...current, ...matchedGuids}.toList());
        }
      } else {
        group = await CustomGroupInterface.create(name: baseName, chatGuids: matchedGuids);
      }
      existing[baseName] = group;

      final showUnreadBadge = entry["showUnreadBadge"] as bool?;
      if (showUnreadBadge != null && showUnreadBadge != group.showUnreadBadge) {
        await CustomGroupInterface.setShowUnreadBadge(id: group.id!, value: showUnreadBadge);
      }
      restored.add(baseName);
    }

    return CustomGroupsRestoreResult(restored: restored, skipped: skipped);
  }
}
