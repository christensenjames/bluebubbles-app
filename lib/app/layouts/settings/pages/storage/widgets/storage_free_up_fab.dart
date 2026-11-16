import 'package:bluebubbles/app/components/m3e/m3e_motion.dart';
import 'package:bluebubbles/app/layouts/settings/pages/storage/storage_analyzer_controller.dart';
import 'package:bluebubbles/app/layouts/settings/pages/storage/storage_analyzer_helpers.dart';
import 'package:bluebubbles/app/layouts/settings/pages/storage/widgets/storage_cleanup_sheet.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

class StorageFreeUpFab extends StatelessWidget with StorageAnalyzerHelpersMixin {
  const StorageFreeUpFab({super.key, required this.controller});

  final StorageAnalyzerController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final hasSelection = controller.selectedSegments.isNotEmpty;
      final label = "Free up ${formatBytes(controller.selectedBytes)}";

      return IgnorePointer(
        ignoring: !hasSelection,
        child: AnimatedScale(
          scale: hasSelection ? 1.0 : 0.9,
          duration: hasSelection ? M3EMotion.spatialFast.durationOf(context) : M3EMotion.effectsFast.durationOf(context),
          curve: hasSelection ? M3EMotion.spatialFast.curve : M3EMotion.effectsFast.curve,
          child: AnimatedOpacity(
            opacity: hasSelection ? 1.0 : 0.0,
            duration: M3EMotion.effectsFast.durationOf(context),
            curve: M3EMotion.effectsFast.curve,
            child: FloatingActionButton.extended(
              onPressed: () => showStorageCleanupSheet(context, controller),
              backgroundColor: context.theme.colorScheme.primary,
              foregroundColor: context.theme.colorScheme.onPrimary,
              icon: Icon(context.iOS ? CupertinoIcons.trash : Icons.delete_outline),
              label: Text(label),
            ),
          ),
        ),
      );
    });
  }
}
