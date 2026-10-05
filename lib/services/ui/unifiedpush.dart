import 'package:bluebubbles/services/services.dart';
import 'package:get/get.dart';

UnifiedPushPanelRefresh upr = Get.isRegistered<UnifiedPushPanelRefresh>()
    ? Get.find<UnifiedPushPanelRefresh>()
    : Get.put(UnifiedPushPanelRefresh());

class UnifiedPushPanelRefresh extends GetxService {
  var enabled = SettingsSvc.settings.enableUnifiedPush.value.obs;

  void update(String newEndpoint) {
    enabled.value = newEndpoint != "";
    SettingsSvc.settings.endpointUnifiedPush.value = newEndpoint;
    SettingsSvc.settings.enableUnifiedPush.value = enabled.value;
    SettingsSvc.settings.saveManyAsync(['endpointUnifiedPush', 'enableUnifiedPush']);
  }
}
