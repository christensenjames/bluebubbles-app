import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/conversation_list/widgets/tile/conversation_tile.dart';
import 'package:bluebubbles/app/layouts/conversation_list/pages/conversation_list.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ListItem extends StatelessWidget {
  final Chat chat;
  final ConversationListController controller;
  final VoidCallback update;
  const ListItem({super.key, required this.chat, required this.controller, required this.update});

  MaterialSwipeAction get leftAction => SettingsSvc.settings.materialLeftAction.value;
  MaterialSwipeAction get rightAction => SettingsSvc.settings.materialRightAction.value;

  Widget slideBackground(BuildContext context, bool left) {
    final action = left ? leftAction : rightAction;
    final colors = context.theme.colorScheme;
    final (Color background, Color foreground) = switch (action) {
      MaterialSwipeAction.pin => (colors.tertiaryContainer, colors.onTertiaryContainer),
      MaterialSwipeAction.alerts => (colors.secondaryContainer, colors.onSecondaryContainer),
      MaterialSwipeAction.mark_read => (colors.primaryContainer, colors.onPrimaryContainer),
      MaterialSwipeAction.archive => (colors.primary, colors.onPrimary),
      MaterialSwipeAction.delete => (colors.error, colors.onError),
    };

    return Container(
      color: background,
      child: Align(
        alignment: left ? Alignment.centerRight : Alignment.centerLeft,
        child: Row(
          mainAxisAlignment: left ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: <Widget>[
            const SizedBox(
              width: 20,
            ),
            Icon(
              action == MaterialSwipeAction.pin
                  ? (chat.isPinned! ? Icons.star_outline : Icons.star)
                  : action == MaterialSwipeAction.alerts
                      ? (chat.muteType == "mute" ? Icons.notifications_active : Icons.notifications_off)
                      : action == MaterialSwipeAction.delete
                          ? Icons.delete_forever_outlined
                          : action == MaterialSwipeAction.mark_read
                              ? (chat.hasUnreadMessage! ? Icons.mark_chat_read : Icons.mark_chat_unread)
                              : (chat.isArchived! ? Icons.unarchive : Icons.archive),
              color: foreground,
            ),
            Text(
              action == MaterialSwipeAction.pin
                  ? (chat.isPinned! ? " Unpin" : " Pin")
                  : action == MaterialSwipeAction.alerts
                      ? (chat.muteType == "mute" ? ' Show Alerts' : ' Hide Alerts')
                      : action == MaterialSwipeAction.delete
                          ? " Delete"
                          : action == MaterialSwipeAction.mark_read
                              ? (chat.hasUnreadMessage! ? ' Mark Read' : ' Mark Unread')
                              : (chat.isArchived! ? ' Unarchive' : ' Archive'),
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
              textAlign: left ? TextAlign.right : TextAlign.left,
            ),
            const SizedBox(
              width: 20,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // No need for Obx here - ConversationTile handles its own reactivity
    final tile = ConversationTile(
      key: Key(chat.guid),
      chat: chat,
      controller: controller,
      onSelect: (bool isSelected) {
        if (isSelected) {
          controller.selectedChats.add(chat);
          controller.updateSelectedChats();
        } else {
          controller.selectedChats.removeWhere((element) => element.guid == chat.guid);
          controller.updateSelectedChats();
        }
      },
    );

    // Swipe settings are hidden on desktop and web, so a mouse drag must not trigger a swipe action there.
    if (kIsDesktop || kIsWeb || !SettingsSvc.settings.swipableConversationTiles.value) return tile;

    return Dismissible(
      key: ValueKey(chat.guid),
      background: Obx(() => slideBackground(context, false)),
      secondaryBackground: Obx(() => slideBackground(context, true)),
      confirmDismiss: (direction) async {
        final action = direction == DismissDirection.endToStart ? leftAction : rightAction;
        switch (action) {
          case MaterialSwipeAction.pin:
            final chatState = ChatsSvc.getChatState(chat.guid);
            ChatsSvc.setChatPinned(chatState?.chat ?? chat, !chat.isPinned!);
          case MaterialSwipeAction.alerts:
            final chatState = ChatsSvc.getChatState(chat.guid);
            if (chatState != null) {
              ChatsSvc.setChatMuted(chatState.chat, chat.muteType != "mute");
            } else {
              chat.toggleMuteAsync(chat.muteType != "mute");
            }
          case MaterialSwipeAction.mark_read:
            final chatState = ChatsSvc.getChatState(chat.guid);
            if (chatState != null) {
              ChatsSvc.setChatHasUnread(chatState.chat, !chat.hasUnreadMessage!);
            } else {
              chat.toggleHasUnreadAsync(!chat.hasUnreadMessage!);
            }
          case MaterialSwipeAction.archive:
            if (controller.showSpam) {
              final chatState = ChatsSvc.getChatState(chat.guid);
              ChatsSvc.setChatArchived(chatState?.chat ?? chat, !chat.isArchived!);
              update.call();
              return false;
            }
            return true;
          case MaterialSwipeAction.delete:
            return true;
        }
        return false;
      },
      onDismissed: (direction) {
        final action = direction == DismissDirection.endToStart ? leftAction : rightAction;
        // Dismissed chats must leave the shown list synchronously.
        if (action == MaterialSwipeAction.delete) {
          final title = ChatsSvc.getChatState(chat.guid)?.title.value ?? chat.getTitle();
          ChatsSvc.removeChat(chat);
          final deleted = ChatsSvc.softDeleteChat(chat);
          var undone = false;
          showSnackbar("Conversation deleted", title, actionLabel: "Undo", onAction: () async {
            if (undone) return;
            undone = true;
            Get.closeAllSnackbars();
            await deleted;
            await ChatsSvc.unDeleteChat(chat, restoreHistory: true);
            await ChatsSvc.addChat(chat, immediate: true);
          });
        } else {
          final chatState = ChatsSvc.getChatState(chat.guid);
          ChatsSvc.setChatArchived(chatState?.chat ?? chat, !chat.isArchived!);
        }
        update.call();
      },
      child: tile,
    );
  }
}
