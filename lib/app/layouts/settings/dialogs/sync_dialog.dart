import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class SyncDialog extends StatefulWidget {
  const SyncDialog({super.key, required this.manager});

  final IncrementalSyncManager manager;

  @override
  State<SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends State<SyncDialog> {
  @override
  Widget build(BuildContext context) {
    return Obx(() => BBProgressDialog(
          title: widget.manager.status.value == SyncStatus.COMPLETED_ERROR
              ? "Sync failed!"
              : widget.manager.progress.value >= 1
                  ? "Done syncing!"
                  : "Syncing messages....",
          progress: widget.manager.progress.value,
          body: widget.manager.status.value == SyncStatus.COMPLETED_ERROR ? Text(widget.manager.error!) : null,
          actions: [
            BBDialogAction(text: "OK", onPressed: () => Navigator.of(context).pop()),
          ],
        ));
  }
}
