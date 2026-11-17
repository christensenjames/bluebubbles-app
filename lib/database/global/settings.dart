import 'dart:async';
import 'dart:convert';

import 'package:async_task/async_task_extension.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/popup/details_menu_action.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/text_field/buttons/text_field_button.dart';
import 'package:bluebubbles/env.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/backend/interfaces/prefs_interface.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart' show Level;
import 'package:universal_io/io.dart';

/// Reads [Settings.linkPreviewPolicy], honoring the boolean that preceded it.
///
/// Installs that saw the interim `fetchUrlPreviews` flag carry their choice
/// forward: off stays off, on becomes the contacts-only default rather than
/// silently re-enabling unconditional fetching.
LinkPreviewPolicy _readLinkPreviewPolicy(Map<String, dynamic> map) {
  final stored = map['linkPreviewPolicy'];
  if (stored is int && stored >= 0 && stored < LinkPreviewPolicy.values.length) {
    return LinkPreviewPolicy.values[stored];
  }

  final legacy = map['fetchUrlPreviews'];
  if (legacy is bool) {
    return legacy ? LinkPreviewPolicy.contactsOnly : LinkPreviewPolicy.never;
  }

  return LinkPreviewPolicy.contactsOnly;
}

class Settings {
  final RxString iMessageStatsSource = "server".obs;
  final RxInt firstFcmRegisterDate = 0.obs;
  final RxString iCloudAccount = "".obs;
  final RxString guidAuthKey = "".obs;
  final RxString serverAddress = "".obs;
  final RxString serverCertificateFingerprint = "".obs;
  final Rx<Map<String, String>> customHeaders = Rx<Map<String, String>>(<String, String>{});
  final RxBool finishedSetup = false.obs;
  final RxBool reachedConversationList = false.obs;
  final RxBool autoDownload = true.obs;
  final RxBool onlyWifiDownload = false.obs;
  final RxBool lowQualityImagesOnCellular = true.obs;
  final RxInt maxConcurrentDownloads = 2.obs;
  final RxBool autoSave = false.obs;
  final RxString autoSavePicsLocation = "Pictures".obs;
  final RxString autoSaveDocsLocation = FilesystemService.androidDownloadsPath.obs;
  final RxDouble previewImageQuality = 1.0.obs; // 0.25 to 1.0
  final RxBool autoOpenKeyboard = true.obs;
  final RxBool hideTextPreviews = false.obs;

  /// When the app may contact a linked website to build a preview card.
  ///
  /// Defaults to [LinkPreviewPolicy.contactsOnly]: links from people the user
  /// has saved load automatically, links from unknown senders wait for a tap.
  /// Previews supplied by the server as part of Apple's payload data are
  /// unaffected — no outbound request is involved.
  final Rx<LinkPreviewPolicy> linkPreviewPolicy = LinkPreviewPolicy.contactsOnly.obs;
  final RxBool showIncrementalSync = false.obs;
  final RxBool highPerfMode = false.obs;
  final RxBool reduceMotion = false.obs;
  final RxInt lastIncrementalSync = 0.obs;
  final RxInt lastIncrementalSyncRowId = 0.obs;
  final RxInt refreshRate = 0.obs;

  /// `CacheService` purge level applied when the app is backgrounded on mobile:
  /// "off", "light", "moderate" or "aggressive". Starts minor on purpose.
  final RxString cachePurgeBackgroundLevel = "light".obs;

  /// `CacheService` purge level applied on an OS memory-pressure signal.
  final RxString cachePurgeMemoryPressureLevel = "moderate".obs;

  /// Comma-separated `ClearableCache.id`s that automatic purges leave alone.
  final RxString cachePurgeExcludedCaches = "".obs;
  final RxBool colorfulAvatars = false.obs;
  final RxBool colorfulBubbles = false.obs;
  final RxBool hideDividers = false.obs;
  final RxDouble scrollVelocity = 1.00.obs;
  final RxBool sendWithReturn = false.obs;
  final RxBool doubleTapForDetails = false.obs;
  final RxBool denseChatTiles = false.obs;
  final RxBool smartReply = false.obs;
  final RxBool showSyncIndicator = true.obs;
  final RxInt sendDelay = 0.obs;
  final RxBool recipientAsPlaceholder = false.obs;
  final RxBool hideKeyboardOnScroll = false.obs;
  final RxBool moveChatCreatorToHeader = false.obs;
  final RxBool showFiltersInHeader = false.obs;
  final RxBool showCustomGroupFilterChips = false.obs;
  final RxBool cameraFAB = false.obs;
  final RxBool swipeToCloseKeyboard = false.obs;
  final RxBool swipeToOpenKeyboard = false.obs;
  final RxBool openKeyboardOnSTB = false.obs;
  final RxBool swipableConversationTiles = false.obs;
  final RxBool showDeliveryTimestamps = false.obs;
  final RxBool filteredChatList = false.obs;
  final RxBool startVideosMuted = true.obs;
  final RxBool startVideosMutedFullscreen = true.obs;
  final RxBool use24HrFormat = false.obs;
  final RxBool alwaysShowAvatars = false.obs;
  final RxBool notifyOnChatList = false.obs;
  final RxBool notifyReactions = true.obs;
  final RxBool colorsFromMedia = false.obs;
  final RxString globalTextDetection = "".obs;
  final RxBool filterUnknownSenders = false.obs;
  /// Dimension name -> enum name (e.g. `{"read": "unread", "type": "group"}`).
  final Rx<Map<String, String>> savedChatFilters = Rx<Map<String, String>>(<String, String>{});
  final RxBool tabletMode = true.obs;
  final RxBool highlightSelectedChat = true.obs;
  final RxBool immersiveMode = true.obs;
  final RxDouble avatarScale = 1.0.obs;
  final RxDouble animationSpeed = 1.0.obs;
  final RxBool askWhereToSave = false.obs;
  final RxBool statusIndicatorsOnChats = false.obs;
  final RxInt apiTimeout = 30000.obs;
  final RxBool allowUpsideDownRotation = false.obs;
  final RxBool cancelQueuedMessages = false.obs;
  final RxBool repliesToPrevious = false.obs;
  final RxnString localhostPort = RxnString(null);
  final RxBool useLocalIpv6 = false.obs;
  final RxnString sendSoundPath = RxnString();
  final RxnString receiveSoundPath = RxnString();
  final RxInt soundVolume = 100.obs;
  final RxBool syncContactsAutomatically = false.obs;
  /// Device account to sync contacts from, e.g. "user@gmail.com" (Android's
  /// `Account.name`). Null means "all accounts" — the default, unfiltered
  /// behavior. Must be set together with [contactSyncAccountType].
  final RxnString contactSyncAccountName = RxnString();
  /// Device account type to sync contacts from, e.g. "com.google" (Android's
  /// `Account.type`). Null means "all accounts". Must be set together with
  /// [contactSyncAccountName].
  final RxnString contactSyncAccountType = RxnString();
  final RxBool scrollToBottomOnSend = true.obs;
  final RxBool sendEventsToTasker = false.obs;
  final RxBool keepAppAlive = false.obs;
  final RxBool unarchiveOnNewMessage = true.obs;
  final RxBool scrollToLastUnread = false.obs;
  final RxString userName = "You".obs;
  final RxBool hideNamesForReactions = false.obs;
  final RxBool replaceEmoticonsWithEmoji = false.obs;

  // final RxString emojiFontFamily;

  // Private API features
  final RxnBool serverPrivateAPI = RxnBool();
  final RxBool enablePrivateAPI = false.obs;
  final RxBool privateSendTypingIndicators = false.obs;
  final RxBool privateMarkChatAsRead = false.obs;
  final RxBool privateManualMarkAsRead = false.obs;
  final RxBool privateSubjectLine = false.obs;
  final RxBool privateAPISend = false.obs;
  final RxBool privateAPIAttachmentSend = false.obs;
  final RxBool editLastSentMessageOnUpArrow = false.obs;
  final RxInt lastReviewRequestTimestamp = 0.obs;

  // Redacted Mode Settings
  final RxBool redactedMode = false.obs;
  final RxBool hideAttachments = true.obs;
  final RxBool hideContactInfo = true.obs;
  final RxBool generateFakeAvatars = false.obs;
  final RxBool hideMessageContent = false.obs;

  // Unified Push Settings
  final RxBool enableUnifiedPush = false.obs;
  final RxString endpointUnifiedPush = RxString("");

  // FCM (Firebase) push delivery — Android's default notification transport. Turn off to
  // skip Firebase registration when using another provider (e.g. UnifiedPush) or the
  // background service; the server then drops the device via its inactivity purge.
  final RxBool enableFcm = true.obs;

  // Quick tapback settings
  final RxBool enableQuickTapback = false.obs;
  final RxString quickTapbackType = ReactionTypes.toList()[0].obs; // The 'love' reaction

  // Notification reaction settings
  final RxBool notificationReactionAction = true.obs;
  final RxString notificationReactionActionType = ReactionTypes.LIKE.obs; // Default to 'like'

  // Slideable action settings
  final Rx<MaterialSwipeAction> materialRightAction = MaterialSwipeAction.pin.obs;
  final Rx<MaterialSwipeAction> materialLeftAction = MaterialSwipeAction.archive.obs;

  // Security settings
  final RxBool shouldSecure = RxBool(false);
  final Rx<SecurityLevel> securityLevel = Rx<SecurityLevel>(SecurityLevel.locked);
  final RxBool incognitoKeyboard = RxBool(false);

  final Rx<Skins> skin = Skins.iOS.obs;
  final Rx<ThemeMode> theme = ThemeMode.system.obs;
  final Rx<SwipeDirection> fullscreenViewerSwipeDir = SwipeDirection.RIGHT.obs;

  // Pin settings
  final RxInt pinRowsPortrait = RxInt(3);
  final RxInt pinColumnsPortrait = RxInt(3);
  final RxInt pinRowsLandscape = RxInt(1);
  final RxInt pinColumnsLandscape = RxInt(4);

  final RxInt maxAvatarsInGroupWidget = RxInt(4);

  // Desktop settings
  final RxBool launchAtStartup = false.obs;
  final RxBool launchAtStartupMinimized = false.obs;
  final RxBool minimizeToTray = false.obs;
  final RxBool closeToTray = true.obs;
  final RxBool spellcheck = true.obs;
  final RxString spellcheckLanguage = "auto".obs;
  final Rx<WindowEffect> windowEffect = WindowEffect.disabled.obs;
  final RxDouble windowEffectCustomOpacityLight = 0.5.obs;
  final RxDouble windowEffectCustomOpacityDark = 0.5.obs;
  final RxBool desktopNotifications = true.obs;
  final RxInt desktopNotificationSoundVolume = 100.obs;
  final RxnString desktopNotificationSoundPath = RxnString();
  final RxBool windowsTaskbarBadge = true.obs;
  final RxBool showTrayIcon = true.obs;

  // Troubleshooting settings
  final Rx<Level> logLevel = Level.info.obs;

  // Notification actions
  final RxBool showReplyField = true.obs;
  final RxList<int> selectedActionIndices = Platform.isWindows ? [0, 1, 2, 3].obs : [0, 1, 2].obs;
  final RxList<String> actionList = RxList.from([
    "Mark Read",
    ReactionTypes.LOVE,
    ReactionTypes.LIKE,
    ReactionTypes.LAUGH,
    ReactionTypes.EMPHASIZE,
    ReactionTypes.DISLIKE,
    ReactionTypes.QUESTION
  ]);

  // Text field buttons — enabled buttons, in display order. Absent = hidden.
  final RxList<TextFieldButton> textFieldButtons = RxList.from(TextFieldButton.values);

  final RxList<String> recentEmojis = RxList<String>([]);

  // Message options order
  final RxList<DetailsMenuAction> _detailsMenuActions = RxList.from(DetailsMenuAction.values);

  /// Use [setDetailsMenuActions] to set this value
  List<DetailsMenuAction> get detailsMenuActions => _detailsMenuActions;

  // Linux settings
  final Rx<BBTitleBarStyle> titleBarStyle = BBTitleBarStyle.custom.obs;

  // Desktop settings
  final RxBool useDesktopAccent = RxBool(false);

  bool get closeToTrayEffective => showTrayIcon.value && closeToTray.value;
  bool get minimizeToTrayEffective => showTrayIcon.value && minimizeToTray.value;

  Future<DisplayMode> getDisplayMode() async {
    List<DisplayMode> modes = await FlutterDisplayMode.supported;
    return modes.firstWhereOrNull((element) => element.refreshRate.round() == refreshRate.value) ?? DisplayMode.auto;
  }

  Future<void> _savePref(String key, dynamic value) async {
    if (value is bool) {
      await PrefsSvc.admin.setBool(key, value);
    } else if (value is String) {
      await PrefsSvc.admin.setString(key, value);
    } else if (value is int) {
      await PrefsSvc.admin.setInt(key, value);
    } else if (value is double) {
      await PrefsSvc.admin.setDouble(key, value);
    } else if (value is List<DetailsMenuAction>) {
      await PrefsSvc.admin.setString(key, jsonEncode(value.map((action) => action.name).toList()));
    } else if (value is List || value is Map) {
      await PrefsSvc.admin.setString(key, jsonEncode(value));
    } else if (value == null) {
      await PrefsSvc.admin.remove(key);
    }
  }

  Settings save() {
    Map<String, dynamic> map = toMap();
    map.forEach((key, value) async {
      await _savePref(key, value);
    });
    return this;
  }

  Future<Settings> saveAsync() async {
    Map<String, dynamic> map = toMap();

    // Ensure the GlobalIsolate's settings are also updated
    await PrefsInterface.syncAllSettings(settings: map);

    // Wait for each key to be saved before moving on
    await Future.forEach(map.entries, (entry) async {
      await _savePref(entry.key, entry.value);
    });

    return this;
  }

  Future<Settings> saveOneAsync(String key) async {
    Map<String, dynamic> map = toMap();
    if (map.containsKey(key)) {
      // Ensure the GlobalIsolate's settings are also updated
      await PrefsInterface.syncSettings({key: map[key]});
      await _savePref(key, map[key]);
    }

    return this;
  }

  Future<Settings> saveManyAsync(List<String> keys) async {
    Map<String, dynamic> map = toMap();
    map.removeWhere((key, value) => !keys.contains(key));

    // Ensure the GlobalIsolate's settings are also updated
    await PrefsInterface.syncSettings(map);

    for (String key in keys) {
      if (map.containsKey(key)) {
        await _savePref(key, map[key]);
      }
    }

    return this;
  }

  static Settings getSettings() {
    Set<String> keys = PrefsSvc.admin.getKeys();

    Map<String, dynamic> items = {};
    for (String s in keys) {
      items[s] = PrefsSvc.admin.get(s);
    }
    if (items.isNotEmpty) {
      return Settings.fromMap(items);
    } else {
      return Settings();
    }
  }

  /// Per-device keys left out of backups.
  static const deviceLocalKeys = [
    'iCloudAccount',
    'guidAuthKey',
    'serverAddress',
    'serverCertificateFingerprint',
    'customHeaders',
    'finishedSetup',
    'reachedConversationList',
    'colorsFromMedia',
    'userAvatarPath',
    'firstFcmRegisterDate',
    'sendSoundPath',
    'receiveSoundPath',
    'desktopNotificationSoundPath',
    'lastIncrementalSync',
    'lastIncrementalSyncRowId',
    'contactSyncAccountName',
    'contactSyncAccountType',
    'enableUnifiedPush',
    'endpointUnifiedPush',
    'enableFcm',
  ];

  Map<String, dynamic> toMap({bool includeAll = true}) {
    Map<String, dynamic> map = {
      'autoDownload': autoDownload.value,
      'onlyWifiDownload': onlyWifiDownload.value,
      'lowQualityImagesOnCellular': lowQualityImagesOnCellular.value,
      'maxConcurrentDownloads': maxConcurrentDownloads.value,
      'autoSave': autoSave.value,
      'autoSavePicsLocation': autoSavePicsLocation.value,
      'autoSaveDocsLocation': autoSaveDocsLocation.value,
      'imageQuality': previewImageQuality.value,
      'autoOpenKeyboard': autoOpenKeyboard.value,
      'hideTextPreviews': hideTextPreviews.value,
      'linkPreviewPolicy': linkPreviewPolicy.value.index,
      'showIncrementalSync': showIncrementalSync.value,
      'highPerfMode': highPerfMode.value,
      'reduceMotion': reduceMotion.value,
      'refreshRate': refreshRate.value,
      'colorfulAvatars': colorfulAvatars.value,
      'colorfulBubbles': colorfulBubbles.value,
      'hideDividers': hideDividers.value,
      'scrollVelocity': scrollVelocity.value,
      'sendWithReturn': sendWithReturn.value,
      'doubleTapForDetails': doubleTapForDetails.value,
      'denseChatTiles': denseChatTiles.value,
      'smartReply': smartReply.value,
      'showSyncIndicator': showSyncIndicator.value,
      'sendDelay': sendDelay.value,
      'recipientAsPlaceholder': recipientAsPlaceholder.value,
      'hideKeyboardOnScroll': hideKeyboardOnScroll.value,
      'moveChatCreatorToHeader': moveChatCreatorToHeader.value,
      'showFiltersInHeader': showFiltersInHeader.value,
      'showCustomGroupFilterChips': showCustomGroupFilterChips.value,
      'cameraFAB': cameraFAB.value,
      'swipeToCloseKeyboard': swipeToCloseKeyboard.value,
      'swipeToOpenKeyboard': swipeToOpenKeyboard.value,
      'openKeyboardOnSTB': openKeyboardOnSTB.value,
      'swipableConversationTiles': swipableConversationTiles.value,
      'showDeliveryTimestamps': showDeliveryTimestamps.value,
      'filteredChatList': filteredChatList.value,
      'startVideosMuted': startVideosMuted.value,
      'startVideosMutedFullscreen': startVideosMutedFullscreen.value,
      'use24HrFormat': use24HrFormat.value,
      'alwaysShowAvatars': alwaysShowAvatars.value,
      'notifyOnChatList': notifyOnChatList.value,
      'notifyReactions': notifyReactions.value,
      'globalTextDetection': globalTextDetection.value,
      'filterUnknownSenders': filterUnknownSenders.value,
      'savedChatFilters': Map<String, String>.from(savedChatFilters.value),
      'tabletMode': tabletMode.value,
      'immersiveMode': immersiveMode.value,
      'avatarScale': avatarScale.value,
      'animationSpeed': animationSpeed.value,
      'launchAtStartup': launchAtStartup.value,
      'launchAtStartupMinimized': launchAtStartupMinimized.value,
      'closeToTray': closeToTray.value,
      'spellcheck': spellcheck.value,
      'spellcheckLanguage': spellcheckLanguage.value,
      'minimizeToTray': minimizeToTray.value,
      'showReplyField': showReplyField.value,
      'selectedActionIndices': List<int>.from(selectedActionIndices),
      'actionList': List<String>.from(actionList),
      'detailsMenuActions': detailsMenuActions.map((action) => action.name).toList(),
      'textFieldButtons': textFieldButtons.map((button) => button.name).toList(),
      'recentEmojis': List<String>.from(recentEmojis),
      'askWhereToSave': askWhereToSave.value,
      'statusIndicatorsOnChats': statusIndicatorsOnChats.value,
      'apiTimeout': apiTimeout.value,
      'allowUpsideDownRotation': allowUpsideDownRotation.value,
      'cancelQueuedMessages': cancelQueuedMessages.value,
      'repliesToPrevious': repliesToPrevious.value,
      'useLocalhost': localhostPort.value,
      'useLocalIpv6': useLocalIpv6.value,
      'soundVolume': soundVolume.value,
      'syncContactsAutomatically': syncContactsAutomatically.value,
      'contactSyncAccountName': contactSyncAccountName.value,
      'contactSyncAccountType': contactSyncAccountType.value,
      'scrollToBottomOnSend': scrollToBottomOnSend.value,
      'sendEventsToTasker': sendEventsToTasker.value,
      'keepAppAlive': keepAppAlive.value,
      // Stored under a new key so installs that saved the old default (off) start with it on.
      'autoUnarchiveOnNewMessage': unarchiveOnNewMessage.value,
      'scrollToLastUnread': scrollToLastUnread.value,
      'userName': userName.value,
      'privateAPISend': privateAPISend.value,
      'privateAPIAttachmentSend': privateAPIAttachmentSend.value,
      'enableUnifiedPush': enableUnifiedPush.value,
      'endpointUnifiedPush': endpointUnifiedPush.value,
      'enableFcm': enableFcm.value,
      'highlightSelectedChat': highlightSelectedChat.value,
      'enablePrivateAPI': enablePrivateAPI.value,
      'privateSendTypingIndicators': privateSendTypingIndicators.value,
      'privateMarkChatAsRead': privateMarkChatAsRead.value,
      'privateManualMarkAsRead': privateManualMarkAsRead.value,
      'privateSubjectLine': privateSubjectLine.value,
      'editLastSentMessageOnUpArrow': editLastSentMessageOnUpArrow.value,
      'redactedMode': redactedMode.value,
      'hideMessageContent': hideMessageContent.value,
      'hideAttachments': hideAttachments.value,
      'hideContactInfo': hideContactInfo.value,
      'generateFakeAvatars': generateFakeAvatars.value,
      'generateFakeMessageContent': hideMessageContent.value,
      'enableQuickTapback': enableQuickTapback.value,
      'quickTapbackType': quickTapbackType.value,
      'notificationReactionAction': notificationReactionAction.value,
      'notificationReactionActionType': notificationReactionActionType.value,
      'materialRightAction': materialRightAction.value.index,
      'materialLeftAction': materialLeftAction.value.index,
      'shouldSecure': shouldSecure.value,
      'securityLevel': securityLevel.value.index,
      'incognitoKeyboard': incognitoKeyboard.value,
      'skin': skin.value.index,
      'theme': theme.value.index,
      'fullscreenViewerSwipeDir': fullscreenViewerSwipeDir.value.index,
      'pinRowsPortrait': pinRowsPortrait.value,
      'pinColumnsPortrait': pinColumnsPortrait.value,
      'pinRowsLandscape': pinRowsLandscape.value,
      'pinColumnsLandscape': pinColumnsLandscape.value,
      'maxAvatarsInGroupWidget': maxAvatarsInGroupWidget.value,
      'titleBarStyle': titleBarStyle.value.index,
      'windowEffect': windowEffect.value.name,
      'windowEffectCustomOpacityLight': windowEffectCustomOpacityLight.value,
      'windowEffectCustomOpacityDark': windowEffectCustomOpacityDark.value,
      'desktopNotifications': desktopNotifications.value,
      'desktopNotificationSoundVolume': desktopNotificationSoundVolume.value,
      'windowsTaskbarBadge': windowsTaskbarBadge.value,
      'showTrayIcon': showTrayIcon.value,
      'useDesktopAccent': useDesktopAccent.value,
      'logLevel': logLevel.value.index,
      'hideNamesForReactions': hideNamesForReactions.value,
      'replaceEmoticonsWithEmoji': replaceEmoticonsWithEmoji.value,
      'lastReviewRequestTimestamp': lastReviewRequestTimestamp.value,
      'serverPrivateAPI': serverPrivateAPI.value,
      'iMessageStatsSource': iMessageStatsSource.value,
      'cachePurgeBackgroundLevel': cachePurgeBackgroundLevel.value,
      'cachePurgeMemoryPressureLevel': cachePurgeMemoryPressureLevel.value,
      'cachePurgeExcludedCaches': cachePurgeExcludedCaches.value,
      'iCloudAccount': iCloudAccount.value,
      'guidAuthKey': guidAuthKey.value,
      'serverAddress': serverAddress.value,
      'serverCertificateFingerprint': serverCertificateFingerprint.value,
      'customHeaders': Map<String, String>.from(customHeaders.value),
      'finishedSetup': finishedSetup.value,
      'reachedConversationList': reachedConversationList.value,
      'colorsFromMedia': colorsFromMedia.value,
      'firstFcmRegisterDate': firstFcmRegisterDate.value,
      'sendSoundPath': sendSoundPath.value,
      'receiveSoundPath': receiveSoundPath.value,
      'desktopNotificationSoundPath': desktopNotificationSoundPath.value,
      'lastIncrementalSync': lastIncrementalSync.value,
      'lastIncrementalSyncRowId': lastIncrementalSyncRowId.value,
    };
    if (!includeAll) map.removeWhere((k, _) => deviceLocalKeys.contains(k));

    return map;
  }

  static const Set<String> _deviceLocalBackupKeys = {
    'serverCertificateFingerprint',
    'lastIncrementalSync',
    'lastIncrementalSyncRowId',
    'contactSyncAccountName',
    'contactSyncAccountType',
    'enableUnifiedPush',
    'endpointUnifiedPush',
    'enableFcm',
  };

  /// Backup map minus state that only means something on the device that produced it.
  static Map<String, dynamic> forBackupRestore(Map<String, dynamic> backup) {
    final map = Map<String, dynamic>.from(backup)..removeWhere((k, _) => _deviceLocalBackupKeys.contains(k));
    if (map['savedChatFilters'] != null) {
      // customGroupIds are ObjectBox row ids of the exporting device.
      map['savedChatFilters'] = Map<String, String>.from(_processSavedChatFilters(map['savedChatFilters']))
        ..remove('customGroupIds');
    }
    return map;
  }

  /// Pass [save] false when the values are already persisted (e.g. forwarded from an isolate that saved them).
  /// Pass [includeAll] false to ignore [deviceLocalKeys].
  static void updateFromMap(Map<String, dynamic> map, {bool save = true, bool includeAll = true}) {
    if (!includeAll) map = Map.of(map)..removeWhere((k, _) => deviceLocalKeys.contains(k));
    SettingsSvc.settings._applyMap(map);
    if (!isIsolate && save) {
      unawaited(SettingsSvc.settings.saveAsync());
      EventDispatcherSvc.emit("theme-update", null);
    }
  }

  static Settings fromMap(Map<String, dynamic> map) => Settings().._applyMap(map, initializing: true);

  void _applyMap(Map<String, dynamic> map, {bool initializing = false}) {
    iCloudAccount.value = map['iCloudAccount'] ?? iCloudAccount.value;
    serverAddress.value = map['serverAddress'] ?? serverAddress.value;
    serverCertificateFingerprint.value =
        map['serverCertificateFingerprint'] ?? serverCertificateFingerprint.value;
    guidAuthKey.value = map['guidAuthKey'] ?? guidAuthKey.value;
    if (map.containsKey('customHeaders')) {
      debugPrint('Updating custom headers from map: ${map['customHeaders']}');
      customHeaders.value = _processCustomHeaders(map['customHeaders']);
    }
    finishedSetup.value = map['finishedSetup'] ?? finishedSetup.value;
    reachedConversationList.value =
        map['reachedConversationList'] ?? reachedConversationList.value;
    autoDownload.value = map['autoDownload'] ?? autoDownload.value;
    onlyWifiDownload.value =
        map['onlyWifiDownload'] ?? onlyWifiDownload.value;
    lowQualityImagesOnCellular.value =
        map['lowQualityImagesOnCellular'] ?? lowQualityImagesOnCellular.value;
    maxConcurrentDownloads.value =
        map['maxConcurrentDownloads'] ?? maxConcurrentDownloads.value;
    autoSave.value = map['autoSave'] ?? autoSave.value;
    autoSavePicsLocation.value =
        map['autoSavePicsLocation'] ?? autoSavePicsLocation.value;
    autoSaveDocsLocation.value =
        map['autoSaveDocsLocation'] ?? autoSaveDocsLocation.value;
    previewImageQuality.value =
        map['imageQuality']?.toDouble() ?? previewImageQuality.value;
    autoOpenKeyboard.value =
        map['autoOpenKeyboard'] ?? autoOpenKeyboard.value;
    hideTextPreviews.value =
        map['hideTextPreviews'] ?? hideTextPreviews.value;
    final hasLinkPreviewPolicy = map.containsKey('linkPreviewPolicy') || map.containsKey('fetchUrlPreviews');
    linkPreviewPolicy.value =
        hasLinkPreviewPolicy ? _readLinkPreviewPolicy(map) : linkPreviewPolicy.value;
    showIncrementalSync.value =
        map['showIncrementalSync'] ?? showIncrementalSync.value;
    highPerfMode.value = map['highPerfMode'] ?? highPerfMode.value;
    reduceMotion.value = map['reduceMotion'] ?? reduceMotion.value;
    lastIncrementalSync.value =
        map['lastIncrementalSync'] ?? lastIncrementalSync.value;
    lastIncrementalSyncRowId.value =
        map['lastIncrementalSyncRowId'] ?? lastIncrementalSyncRowId.value;
    refreshRate.value = map['refreshRate'] ?? refreshRate.value;
    colorfulAvatars.value = map['colorfulAvatars'] ?? colorfulAvatars.value;
    colorfulBubbles.value = map['colorfulBubbles'] ?? colorfulBubbles.value;
    hideDividers.value = map['hideDividers'] ?? hideDividers.value;
    scrollVelocity.value =
        map['scrollVelocity']?.toDouble() ?? scrollVelocity.value;
    sendWithReturn.value = map['sendWithReturn'] ?? sendWithReturn.value;
    doubleTapForDetails.value =
        map['doubleTapForDetails'] ?? doubleTapForDetails.value;
    denseChatTiles.value = map['denseChatTiles'] ?? denseChatTiles.value;
    smartReply.value = map['smartReply'] ?? smartReply.value;
    showSyncIndicator.value =
        map['showSyncIndicator'] ?? showSyncIndicator.value;
    sendDelay.value = map['sendDelay'] ?? sendDelay.value;
    recipientAsPlaceholder.value =
        map['recipientAsPlaceholder'] ?? recipientAsPlaceholder.value;
    hideKeyboardOnScroll.value =
        map['hideKeyboardOnScroll'] ?? hideKeyboardOnScroll.value;
    moveChatCreatorToHeader.value =
        map['moveChatCreatorToHeader'] ?? moveChatCreatorToHeader.value;
    showFiltersInHeader.value =
        map['showFiltersInHeader'] ?? showFiltersInHeader.value;
    showCustomGroupFilterChips.value =
        map['showCustomGroupFilterChips'] ?? showCustomGroupFilterChips.value;
    cameraFAB.value = map['cameraFAB'] ?? cameraFAB.value;
    swipeToCloseKeyboard.value =
        map['swipeToCloseKeyboard'] ?? swipeToCloseKeyboard.value;
    swipeToOpenKeyboard.value =
        map['swipeToOpenKeyboard'] ?? swipeToOpenKeyboard.value;
    openKeyboardOnSTB.value =
        map['openKeyboardOnSTB'] ?? openKeyboardOnSTB.value;
    swipableConversationTiles.value =
        map['swipableConversationTiles'] ?? swipableConversationTiles.value;
    showDeliveryTimestamps.value =
        map['showDeliveryTimestamps'] ?? showDeliveryTimestamps.value;
    filteredChatList.value =
        map['filteredChatList'] ?? filteredChatList.value;
    startVideosMuted.value =
        map['startVideosMuted'] ?? startVideosMuted.value;
    startVideosMutedFullscreen.value =
        map['startVideosMutedFullscreen'] ?? startVideosMutedFullscreen.value;
    use24HrFormat.value = map['use24HrFormat'] ?? use24HrFormat.value;
    alwaysShowAvatars.value =
        map['alwaysShowAvatars'] ?? alwaysShowAvatars.value;
    notifyOnChatList.value =
        map['notifyOnChatList'] ?? notifyOnChatList.value;
    notifyReactions.value = map['notifyReactions'] ?? notifyReactions.value;
    colorsFromMedia.value = map['colorsFromMedia'] ?? colorsFromMedia.value;
    globalTextDetection.value =
        map['globalTextDetection'] ?? globalTextDetection.value;
    filterUnknownSenders.value =
        map['filterUnknownSenders'] ?? filterUnknownSenders.value;
    if (map.containsKey('savedChatFilters')) {
      savedChatFilters.value = _processSavedChatFilters(map['savedChatFilters']);
    }
    tabletMode.value = kIsDesktop || (map['tabletMode'] ?? tabletMode.value);
    highlightSelectedChat.value =
        map['highlightSelectedChat'] ?? highlightSelectedChat.value;
    immersiveMode.value = map['immersiveMode'] ?? immersiveMode.value;
    avatarScale.value = map['avatarScale']?.toDouble() ?? avatarScale.value;
    animationSpeed.value =
        map['animationSpeed']?.toDouble() ?? animationSpeed.value;
    launchAtStartup.value = map['launchAtStartup'] ?? launchAtStartup.value;
    launchAtStartupMinimized.value =
        map['launchAtStartupMinimized'] ?? launchAtStartupMinimized.value;
    closeToTray.value = map['closeToTray'] ?? closeToTray.value;
    spellcheck.value = map['spellcheck'] ?? spellcheck.value;
    spellcheckLanguage.value =
        map['spellcheckLanguage'] ?? spellcheckLanguage.value;
    minimizeToTray.value = map['minimizeToTray'] ?? minimizeToTray.value;
    askWhereToSave.value = map['askWhereToSave'] ?? askWhereToSave.value;
    statusIndicatorsOnChats.value =
        map['statusIndicatorsOnChats'] ?? statusIndicatorsOnChats.value;
    apiTimeout.value = map['apiTimeout'] ?? apiTimeout.value;
    allowUpsideDownRotation.value =
        map['allowUpsideDownRotation'] ?? allowUpsideDownRotation.value;
    cancelQueuedMessages.value =
        map['cancelQueuedMessages'] ?? cancelQueuedMessages.value;
    repliesToPrevious.value =
        map['repliesToPrevious'] ?? repliesToPrevious.value;
    localhostPort.value = map['useLocalhost'] ?? localhostPort.value;
    useLocalIpv6.value = map['useLocalIpv6'] ?? useLocalIpv6.value;
    sendSoundPath.value = map['sendSoundPath'] ?? sendSoundPath.value;
    receiveSoundPath.value =
        map['receiveSoundPath'] ?? receiveSoundPath.value;
    soundVolume.value = map['soundVolume'] ?? soundVolume.value;
    syncContactsAutomatically.value =
        map['syncContactsAutomatically'] ?? syncContactsAutomatically.value;
    contactSyncAccountName.value =
        map['contactSyncAccountName'] ?? contactSyncAccountName.value;
    contactSyncAccountType.value =
        map['contactSyncAccountType'] ?? contactSyncAccountType.value;
    scrollToBottomOnSend.value =
        map['scrollToBottomOnSend'] ?? scrollToBottomOnSend.value;
    sendEventsToTasker.value =
        map['sendEventsToTasker'] ?? sendEventsToTasker.value;
    keepAppAlive.value = map['keepAppAlive'] ?? keepAppAlive.value;
    unarchiveOnNewMessage.value =
        map['autoUnarchiveOnNewMessage'] ?? unarchiveOnNewMessage.value;
    scrollToLastUnread.value =
        map['scrollToLastUnread'] ?? scrollToLastUnread.value;
    userName.value = map['userName'] ?? userName.value;
    privateAPISend.value = map['privateAPISend'] ?? privateAPISend.value;
    privateAPIAttachmentSend.value =
        map['privateAPIAttachmentSend'] ?? privateAPIAttachmentSend.value;
    enablePrivateAPI.value =
        map['enablePrivateAPI'] ?? enablePrivateAPI.value;
    serverPrivateAPI.value =
        map['serverPrivateAPI'] ?? serverPrivateAPI.value;
    iMessageStatsSource.value = map.containsKey('iMessageStatsSource')
        ? (map['iMessageStatsSource'] == 'local' ? 'local' : 'server')
        : iMessageStatsSource.value;
    cachePurgeBackgroundLevel.value =
        map['cachePurgeBackgroundLevel'] ?? cachePurgeBackgroundLevel.value;
    cachePurgeMemoryPressureLevel.value =
        map['cachePurgeMemoryPressureLevel'] ?? cachePurgeMemoryPressureLevel.value;
    cachePurgeExcludedCaches.value =
        map['cachePurgeExcludedCaches'] ?? cachePurgeExcludedCaches.value;
    privateSendTypingIndicators.value =
        map['privateSendTypingIndicators'] ?? privateSendTypingIndicators.value;
    privateMarkChatAsRead.value =
        map['privateMarkChatAsRead'] ?? privateMarkChatAsRead.value;
    privateManualMarkAsRead.value =
        map['privateManualMarkAsRead'] ?? privateManualMarkAsRead.value;
    privateSubjectLine.value =
        map['privateSubjectLine'] ?? privateSubjectLine.value;
    editLastSentMessageOnUpArrow.value =
        map['editLastSentMessageOnUpArrow'] ?? editLastSentMessageOnUpArrow.value;
    redactedMode.value = map['redactedMode'] ?? redactedMode.value;
    hideMessageContent.value =
        map['hideMessageContent'] ?? hideMessageContent.value;
    hideAttachments.value = map['hideAttachments'] ?? hideAttachments.value;
    hideContactInfo.value = map['hideContactInfo'] ?? hideContactInfo.value;
    generateFakeAvatars.value =
        map['generateFakeAvatars'] ?? generateFakeAvatars.value;
    hideMessageContent.value =
        map['generateFakeMessageContent'] ?? hideMessageContent.value;
    enableUnifiedPush.value =
        map['enableUnifiedPush'] ?? enableUnifiedPush.value;
    endpointUnifiedPush.value =
        map['endpointUnifiedPush'] ?? endpointUnifiedPush.value;
    enableFcm.value = map['enableFcm'] ?? enableFcm.value;
    enableQuickTapback.value =
        map['enableQuickTapback'] ?? enableQuickTapback.value;
    quickTapbackType.value =
        map['quickTapbackType'] ?? quickTapbackType.value;
    notificationReactionAction.value =
        map['notificationReactionAction'] ?? notificationReactionAction.value;
    notificationReactionActionType.value =
        map['notificationReactionActionType'] ?? notificationReactionActionType.value;
    materialRightAction.value = map['materialRightAction'] != null
        ? MaterialSwipeAction.values[map['materialRightAction']]
        : materialRightAction.value;
    materialLeftAction.value = map['materialLeftAction'] != null
        ? MaterialSwipeAction.values[map['materialLeftAction']]
        : materialLeftAction.value;
    shouldSecure.value = map['shouldSecure'] ?? shouldSecure.value;
    securityLevel.value = map['securityLevel'] != null
        ? SecurityLevel.values[map['securityLevel']]
        : securityLevel.value;
    incognitoKeyboard.value =
        map['incognitoKeyboard'] ?? incognitoKeyboard.value;
    skin.value = map['skin'] != null ? Skins.values[map['skin']] : skin.value;
    theme.value =
        map['theme'] != null ? ThemeMode.values[map['theme']] : theme.value;
    fullscreenViewerSwipeDir.value = map['fullscreenViewerSwipeDir'] != null
        ? SwipeDirection.values[map['fullscreenViewerSwipeDir']]
        : fullscreenViewerSwipeDir.value;
    pinRowsPortrait.value = map['pinRowsPortrait'] ?? pinRowsPortrait.value;
    pinColumnsPortrait.value =
        map['pinColumnsPortrait'] ?? pinColumnsPortrait.value;
    pinRowsLandscape.value =
        map['pinRowsLandscape'] ?? pinRowsLandscape.value;
    pinColumnsLandscape.value =
        map['pinColumnsLandscape'] ?? pinColumnsLandscape.value;
    maxAvatarsInGroupWidget.value =
        map['maxAvatarsInGroupWidget'] ?? maxAvatarsInGroupWidget.value;
    titleBarStyle.value = map['titleBarStyle'] != null
        ? BBTitleBarStyle.values[map['titleBarStyle']]
        : map['useCustomTitleBar'] == false
            ? BBTitleBarStyle.native
            : titleBarStyle.value;

    showReplyField.value = map['showReplyField'] ?? showReplyField.value;
    if (initializing || map.containsKey('selectedActionIndices')) {
      selectedActionIndices.value =
          _processSelectedActionIndices(map['selectedActionIndices'], showReplyField.value);
    }
    actionList.value =
        _processActionList(map['actionList'] ?? jsonEncode(List<String>.from(actionList)));
    if (map.containsKey('detailsMenuActions')) {
      _detailsMenuActions.value =
          _processDetailsMenuActions(map['detailsMenuActions'], detailsMenuActions);
    }
    if (map.containsKey('textFieldButtons')) {
      textFieldButtons.value = _processTextFieldButtons(map['textFieldButtons']);
    }
    if (map.containsKey('recentEmojis')) {
      recentEmojis.value = _processRecentEmojis(map['recentEmojis']);
    }

    windowEffect.value = kIsDesktop && Platform.isWindows
        ? WindowEffect.values.firstWhereOrNull((e) => e.name == map['windowEffect']) ??
            windowEffect.value
        : windowEffect.value;
    windowEffectCustomOpacityLight.value =
        map['windowEffectCustomOpacityLight']?.toDouble() ?? windowEffectCustomOpacityLight.value;
    windowEffectCustomOpacityDark.value =
        map['windowEffectCustomOpacityDark']?.toDouble() ?? windowEffectCustomOpacityDark.value;
    desktopNotifications.value =
        map['desktopNotifications'] ?? desktopNotifications.value;
    desktopNotificationSoundVolume.value =
        map['desktopNotificationSoundVolume'] ?? desktopNotificationSoundVolume.value;
    windowsTaskbarBadge.value =
        map['windowsTaskbarBadge'] ?? windowsTaskbarBadge.value;
    showTrayIcon.value = map['showTrayIcon'] ?? showTrayIcon.value;
    desktopNotificationSoundPath.value =
        map['desktopNotificationSoundPath'] ?? desktopNotificationSoundPath.value;
    useDesktopAccent.value =
        map['useDesktopAccent'] ?? map['useWindowsAccent'] ?? useDesktopAccent.value;
    firstFcmRegisterDate.value =
        map['firstFcmRegisterDate'] ?? firstFcmRegisterDate.value;
    logLevel.value =
        map['logLevel'] != null ? Level.values[map['logLevel']] : logLevel.value;
    hideNamesForReactions.value =
        map['hideNamesForReactions'] ?? hideNamesForReactions.value;
    replaceEmoticonsWithEmoji.value =
        map['replaceEmoticonsWithEmoji'] ?? replaceEmoticonsWithEmoji.value;
    lastReviewRequestTimestamp.value =
        map['lastReviewRequestTimestamp'] ?? lastReviewRequestTimestamp.value;
  }

  /// function to set detailsMenuActions from a subset of allActions
  void setDetailsMenuActions(List<DetailsMenuAction> actions) {
    SettingsSvc.settings._detailsMenuActions.value =
        _filterDetailsMenuActions(actions, SettingsSvc.settings.detailsMenuActions);
    // saveOneAsync (not save()) so the GlobalIsolate's copy is synced too, else it
    // overwrites this on its next background settings write.
    unawaited(SettingsSvc.settings.saveOneAsync('detailsMenuActions'));
  }

  /// Set the enabled text field buttons, in display order
  void setTextFieldButtons(List<TextFieldButton> buttons) {
    SettingsSvc.settings.textFieldButtons.value = buttons;
    // saveOneAsync (not save()) so the GlobalIsolate's copy is synced too
    unawaited(SettingsSvc.settings.saveOneAsync('textFieldButtons'));
  }

  void resetTextFieldButtons() {
    SettingsSvc.settings.textFieldButtons.value = TextFieldButton.values;
    unawaited(SettingsSvc.settings.saveOneAsync('textFieldButtons'));
  }

  void resetDetailsMenuActions() {
    SettingsSvc.settings._detailsMenuActions.value = DetailsMenuAction.values;
    unawaited(SettingsSvc.settings.saveOneAsync('detailsMenuActions'));
  }

  void addRecentEmojis(Iterable<String> emojis) {
    if (emojis.isEmpty) return;
    final list = List<String>.from(recentEmojis);
    for (final emoji in emojis) {
      list.remove(emoji);
      list.insert(0, emoji);
    }
    if (list.length > 10) {
      list.removeRange(10, list.length);
    }
    recentEmojis.value = list;
    unawaited(saveOneAsync('recentEmojis'));
  }
}

Map<String, String> _processCustomHeaders(dynamic rawJson) {
  try {
    return (rawJson is Map ? rawJson : jsonDecode(rawJson) as Map).cast<String, String>();
  } catch (e) {
    debugPrint("Using default customHeaders");
    return <String, String>{};
  }
}

/// Accepts either an already-decoded [Map] (e.g. synced in-memory to the
/// GlobalIsolate) or a JSON-encoded [String] (round-tripped through disk
/// prefs, which only store primitives/strings).
Map<String, String> _processSavedChatFilters(dynamic rawJson) {
  try {
    return (rawJson is Map ? rawJson : jsonDecode(rawJson) as Map).cast<String, String>();
  } catch (e) {
    return <String, String>{};
  }
}

List<int> _processSelectedActionIndices(dynamic rawJson, bool showReplyField) {
  try {
    return (rawJson is List ? rawJson : jsonDecode(rawJson) as List)
        .cast<int>()
        .take(Platform.isWindows ? (showReplyField ? 4 : 5) : 3)
        .sorted(Comparable.compare);
  } catch (e) {
    debugPrint("Using default selectedActionIndices");
    return [0, 1, 2, 3, 4].take(Platform.isWindows ? (showReplyField ? 4 : 5) : 3).sorted(Comparable.compare);
  }
}

List<String> _processActionList(dynamic rawJson) {
  try {
    return (rawJson is List ? rawJson : jsonDecode(rawJson) as List).cast<String>();
  } catch (e) {
    debugPrint("Using default actionList");
    return [
      "Mark Read",
      ReactionTypes.LOVE,
      ReactionTypes.LIKE,
      ReactionTypes.LAUGH,
      ReactionTypes.EMPHASIZE,
      ReactionTypes.DISLIKE,
      ReactionTypes.QUESTION
    ];
  }
}

List<TextFieldButton> _processTextFieldButtons(dynamic rawJson) {
  try {
    return (rawJson is List ? rawJson : jsonDecode(rawJson) as List)
        .cast<String>()
        .map((s) => TextFieldButton.values.firstWhereOrNull((button) => button.name == s))
        .nonNulls
        .toList();
  } catch (e) {
    debugPrint("Using default textFieldButtons");
    return TextFieldButton.values;
  }
}
List<String> _processRecentEmojis(dynamic rawJson) {
  try {
    return (rawJson is List ? rawJson : jsonDecode(rawJson) as List)
        .whereType<String>()
        .toList();
  } catch (e) {
    return [];
  }
}

List<DetailsMenuAction> _processDetailsMenuActions(dynamic rawJson, List<DetailsMenuAction> allActions) {
  try {
    List<DetailsMenuAction> actions = (rawJson is List ? rawJson : jsonDecode(rawJson) as List)
        .cast<String>()
        .map((s) => DetailsMenuAction.values.firstWhereOrNull((action) => action.name == s))
        .nonNulls
        .toList();
    return _filterDetailsMenuActions(actions, allActions);
  } catch (e) {
    debugPrint("Using default detailsMenuActions");
    return DetailsMenuAction.values;
  }
}

List<DetailsMenuAction> _filterDetailsMenuActions(List<DetailsMenuAction> actions, List<DetailsMenuAction> allActions) {
  // Keep existing order of other keys
  List<(DetailsMenuAction, int)> remainingIndexed =
      allActions.mapIndexed((i, action) => (action, i)).whereNot((mapEntry) => actions.contains(mapEntry.$1)).toList();

  for ((DetailsMenuAction, int) item in remainingIndexed) {
    actions.insert(item.$2, item.$1);
  }

  return actions;
}
