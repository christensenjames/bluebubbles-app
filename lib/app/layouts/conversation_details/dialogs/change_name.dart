import 'dart:async';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

void showChangeName(Chat chat, String method, BuildContext context) {
  final controller = TextEditingController(text: chat.displayName);
  final node = FocusNode();
  late ModalRoute<dynamic> editorRoute;
  showBBDialog(
    context: context,
    title: "Change Name",
    content: Builder(
      builder: (dialogContext) {
        editorRoute = ModalRoute.of(dialogContext)!;
        return TextField(
          controller: controller,
          focusNode: node,
          decoration: const InputDecoration(
            labelText: "Chat Name",
            border: OutlineInputBorder(),
          ),
        );
      },
    ),
    actions: [
      BBDialogAction(
        text: "OK",
        isDefault: true,
        onPressed: () async {
          node.unfocus();
          final nav = Navigator.of(context, rootNavigator: true);
          if (method == "private-api") {
            final progressRoute = DialogRoute<void>(
              context: context,
              themes: InheritedTheme.capture(from: context, to: nav.context),
              barrierColor: Theme.of(context).dialogTheme.barrierColor ?? Colors.black54,
              traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
              builder: (BuildContext context) {
                  return AlertDialog(
                    backgroundColor: context.theme.colorScheme.surfaceContainerHighest,
                    title: Text(
                      controller.text.isEmpty ? "Removing name..." : "Changing name to ${controller.text}...",
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
            nav.push(progressRoute);
            try {
              await HttpSvc.chat.setDisplayName(chat.guid, controller.text);
            } catch (e, s) {
              Logger.error("Failed to update name of ${chat.guid}", error: e, trace: s);
              NavigationSvc.closeRoute(progressRoute);
              showSnackbar("Error", "Failed to update name!");
              return;
            }
            NavigationSvc.closeRoute(progressRoute);
            NavigationSvc.closeRoute(editorRoute);
            unawaited(ChatsSvc.setChatDisplayName(chat, controller.text));
            showSnackbar("Notice", "Updated name successfully!");
          } else {
            Navigator.of(context, rootNavigator: true).pop();
            unawaited(ChatsSvc.setChatDisplayName(chat, controller.text));
          }
        },
      ),
      BBDialogAction(
        text: "Cancel",
        onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
      ),
    ],
  );
}
