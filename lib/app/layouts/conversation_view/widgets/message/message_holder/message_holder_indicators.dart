import 'package:bluebubbles/app/components/m3e/m3e_motion.dart';
import 'package:bluebubbles/app/state/message_state_scope.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/shared/message_error_helper.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/timestamp/delivered_indicator.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Isolated widget for delivered indicator
/// Only rebuilds when tapped state changes
class DeliveredIndicatorObserver extends StatelessWidget {
  const DeliveredIndicatorObserver({
    super.key,
    required this.tapped,
  });

  final RxBool tapped;

  @override
  Widget build(BuildContext context) {
    return Obx(() => DeliveredIndicator(
          forceShow: tapped.value,
        ));
  }
}

/// Isolated widget for error indicator
/// Only rebuilds when error state changes
class ErrorIndicatorObserver extends StatelessWidget {
  const ErrorIndicatorObserver({
    super.key,
    required this.chat,
    required this.service,
  });

  final Chat chat;
  final MessagesService service;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final ms = MessageStateScope.of(context);
      final message = ms.message;
      // Observe MessageState error field directly instead of boolean toggle
      final hasError = ms.hasError.value;

      return AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : M3EMotion.spatialFast.duration,
        curve: M3EMotion.spatialFast.curve,
        alignment: Alignment.centerLeft,
        child: AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Durations.short3,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(animation), child: child),
          ),
          child: hasError
              ? IconButton(
                  tooltip: "Show error details",
                  icon: Icon(
                    SettingsSvc.settings.skin.value == Skins.iOS
                        ? CupertinoIcons.exclamationmark_circle
                        : Icons.error_outline,
                    color: context.theme.colorScheme.error,
                    semanticLabel: "Not delivered",
                  ),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) => MessageErrorDialog(
                        errorCode: message.error,
                        errorText: ErrorHelper.getErrorText(message),
                        chatId: chat.id!,
                        onRetry: () => retryMessage(
                          message: message,
                          chat: chat,
                          service: service,
                          controller: ms,
                        ),
                        onRemove: () async {
                          await service.deleteMessage(message);
                          List<Message> latest = await Chat.getMessagesAsync(chat, limit: 1);
                          ChatsSvc.setChatLatestMessage(chat, latest.first);
                          await chat.saveAsync();
                        },
                      ),
                    );
                  },
                )
              : const SizedBox.shrink(),
        ),
      );
    });
  }
}
