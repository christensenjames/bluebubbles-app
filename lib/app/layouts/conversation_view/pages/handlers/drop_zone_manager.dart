import 'dart:async';
import 'dart:io';

import 'package:bluebubbles/database/global/platform_file.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:universal_io/io.dart';

/// Manages drag-and-drop file operations on the conversation body.
class DropZoneManager {
  final ConversationViewController controller;

  final RxBool dragging = false.obs;

  final RxInt numFiles = 0.obs;

  DropZoneManager({required this.controller});

  void onDropOver(DropEventDetails event) {
    dragging.value = true;
  }

  void onDropLeave(DropEventDetails event) {
    dragging.value = false;
  }

  Widget target({required Widget child}) {
    return DropTarget(
      onDragEntered: onDropOver,
      onDragUpdated: onDropOver,
      onDragExited: onDropLeave,
      onDragDone: onPerformDrop,
      child: child,
    );
  }

  Future<void> onPerformDrop(DropDoneDetails event) async {
    int skipped = 0;
    try {
      for (DropItem item in event.files) {
        if (await FileSystemEntity.type(item.path) != FileSystemEntityType.file) {
          skipped++;
          continue;
        }

        final int size;
        try {
          size = await item.length();
        } on FileSystemException {
          skipped++;
          continue;
        }

        String fileName = item.name;

        if (fileName.isEmpty) {
          fileName = "Dragged_File_${controller.pickedAttachments.length + 1}";
        }

        controller.pickedAttachments.add(PlatformFile(
          name: fileName,
          path: item.path,
          size: size,
          bytes: null,
        ));
      }
    } finally {
      dragging.value = false;
    }

    if (skipped > 0) {
      showSnackbar(
        "Not attached",
        skipped == 1
            ? "1 item isn't a readable file, so it wasn't attached."
            : "$skipped items aren't readable files, so they weren't attached.",
        type: SnackbarType.error,
      );
    }
  }
}
