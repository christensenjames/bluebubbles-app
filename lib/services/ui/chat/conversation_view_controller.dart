import 'dart:async';

import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:bluebubbles/app/components/custom_text_editing_controllers.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/text_field/send_button.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/backend/interfaces/prefs_interface.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_keyboard_visibility/flutter_keyboard_visibility.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:bluebubbles/services/ui/chat/send_data.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/models/models.dart' show MessageReplyContext;
import 'package:unicode_emojis/unicode_emojis.dart';

class MessageEditEntry {
  final Message message;
  final MessagePart part;
  final SpellCheckTextEditingController controller;
  const MessageEditEntry({required this.message, required this.part, required this.controller});
}

ConversationViewController cvc(Chat chat, {String? tag}) =>
    Get.isRegistered<ConversationViewController>(tag: tag ?? chat.guid)
        ? Get.find<ConversationViewController>(tag: tag ?? chat.guid)
        : Get.put(ConversationViewController(chat, tag_: tag), tag: tag ?? chat.guid, permanent: true);

// The send-effect picker creates one ticker per effect preview, so this provider must allow many.
class ConversationViewController extends StatefulController with GetTickerProviderStateMixin {
  final Chat chat;
  late final String tag;
  bool fromChatCreator = false;
  bool fromSearchResult = false;

  /// The ConversationView that may delete this controller. Moving across the tablet breakpoint builds the new view
  /// before disposing the old one, and both share this controller.
  Object? viewOwner;
  bool addedRecentPhotoReply = false;
  bool inSplitPane = false;
  final AutoScrollController scrollController = AutoScrollController();
  bool _composerDisposed = false;
  bool _loggedTypingIntoDisposed = false;

  String get composerIds => 'cvc ${identityHashCode(this).toRadixString(16)}, '
      'text ${identityHashCode(textController).toRadixString(16)}, '
      'focus ${identityHashCode(focusNode).toRadixString(16)}';

  void logTypingIntoDisposedComposer() {
    if (!_composerDisposed || _loggedTypingIntoDisposed) return;
    _loggedTypingIntoDisposed = true;
    Logger.debug('Typing into a disposed composer for ${chat.guid} ($composerIds)', tag: 'Composer');
  }

  ConversationViewController(this.chat, {String? tag_}) {
    tag = tag_ ?? chat.guid;
  }

  // caching items
  final Map<String, VideoController> videoPlayers = {};
  final Map<String, PlayerController> audioPlayers = {};
  final Map<String, Player> audioPlayersDesktop = {};
  final Map<String, List<EntityAnnotation>> mlKitParsedText = {};

  // message view items
  final RxBool showTypingIndicator = false.obs;
  final RxBool showScrollDown = false.obs;
  final RxDouble timestampOffset = 0.0.obs;
  final RxBool inSelectMode = false.obs;
  final RxList<Message> selected = <Message>[].obs;
  final RxList<MessageEditEntry> editing = <MessageEditEntry>[].obs;
  final GlobalKey focusInfoKey = GlobalKey();
  final GlobalKey typingInfoKey = GlobalKey();
  final RxBool recipientNotifsSilenced = false.obs;
  final RxBool showPillRow = false.obs;
  final RxDouble pillRowHeight = 0.0.obs;

  /// Whether the pill row holds any quick action. The row shows two kinds of pill: smart replies (ML suggestions,
  /// cleared when an outgoing message lands) and quick actions (the app's own "Attach recent photo" and "Jump to
  /// oldest unread", which are not). A row with a quick action therefore keeps its height through a send, and
  /// [SendAnimation] reads this to decide whether to leave that height in its landing target.
  bool pillRowHasQuickActions = false;
  bool showingOverlays = false;

  /// True while a pointer is actively dragging a [CollectionGroupStack] fan of
  /// cards, so the list-wide timestamp-reveal swipe in [MessagesView] can
  /// ignore that drag instead of fighting the collection stack for the same gesture.
  bool isCollectionDragging = false;

  /// Media collection grids the user expanded with a `+N` long-press, keyed by
  /// `CollectionGroupGrid.expansionKey`. Lives here rather than in the grid's
  /// State so a grid stays expanded after scrolling off screen and back, for as
  /// long as the conversation is open.
  final Set<String> expandedCollectionGrids = {};

  /// True while any route is pushed on top of the conversation view route (e.g.
  /// ConversationDetails). Used by onAppResume to skip keyboard auto-focus on mobile.
  bool showingSubRoute = false;
  bool _subjectWasLastFocused = false; // If this is false, then message field was last focused (default)

  FocusNode get lastFocusedNode => _subjectWasLastFocused ? subjectFocusNode : focusNode;
  SpellCheckTextEditingController get lastFocusedTextController =>
      _subjectWasLastFocused ? subjectTextController : textController;

  // text field items
  final RxBool showAttachmentPicker = false.obs;

  /// OpenPigeon's game picker, shown below the text field in the keyboard's place.
  final RxBool showGamePicker = false.obs;

  /// Formatting and text effects, shown below the text field in the keyboard's place (mobile).
  final RxBool showTextFormattingPanel = false.obs;

  /// Whether this chat can send formatted text: formatted text goes out as a multipart message, which needs the
  /// Private API, an iMessage chat, and a server that sends `textFormatting`.
  bool get canFormatText =>
      SettingsSvc.settings.enablePrivateAPI.value && chat.isIMessage && SettingsSvc.serverDetails.supportsTextFormatting;

  /// The keyboard's height when the panel last opened, so swapping one for the other doesn't move the field.
  double textFormattingPanelHeight = 300;
  /// The mobile attachment picker's grid is showing the Genmoji library rather than photos.
  /// Lives here so the conversation view's back handler can step back to photos before it
  /// closes the picker. The picker resets it to false each time it opens.
  final RxBool showGenmojiLibrary = false.obs;

  /// The same, for the Mac's sticker library. At most one of the two is set.
  final RxBool showStickerLibrary = false.obs;
  final GlobalKey textFieldKey = GlobalKey();
  final GlobalKey<SendButtonState> sendButtonKey = GlobalKey<SendButtonState>();
  final RxList<PlatformFile> pickedAttachments = <PlatformFile>[].obs;

  /// An OpenPigeon game picked from the game picker, sent with the next send.
  final Rxn<Map<String, dynamic>> pendingGame = Rxn<Map<String, dynamic>>();
  final focusNode = FocusNode();
  final subjectFocusNode = FocusNode();
  late final textController = MentionTextEditingController(focusNode: focusNode);
  late final subjectTextController = SpellCheckTextEditingController(focusNode: subjectFocusNode);
  final RxBool showRecording = false.obs;
  final RxList<Emoji> emojiMatches = <Emoji>[].obs;
  final RxInt emojiSelectedIndex = 0.obs;
  final RxList<Mentionable> mentionMatches = <Mentionable>[].obs;
  final RxInt mentionSelectedIndex = 0.obs;
  final ScrollController emojiScrollController = ScrollController();
  final Rxn<DateTime> scheduledDate = Rxn<DateTime>(null);
  final Rxn<MessageReplyContext> _replyToMessage = Rxn<MessageReplyContext>(null);
  MessageReplyContext? get replyToMessage => _replyToMessage.value;
  set replyToMessage(MessageReplyContext? m) {
    _replyToMessage.value = m;
    if (m != null) {
      lastFocusedNode.requestFocus();
    }
  }

  late final mentionables = chat.people
      .map((e) => Mentionable(
            handle: e,
          ))
      .toList();

  bool keyboardOpen = false;
  double _keyboardOffset = 0;
  StreamSubscription<bool>? _keyboardSub;
  Timer? _scrollDownDebounce;
  Timer? _typingTimer;
  StreamSubscription? _newMessageSub;
  Future<void> Function(SendData)? sendFunc;

  /// When set, [_SendAnimationState] will auto-fire this send as soon as it
  /// registers [sendFunc] (i.e. immediately after the widget is built).
  /// Used by ChatCreator to pre-queue a send before navigating to ConversationView.
  SendData? pendingSend;

  /// Completer that resolves once [MessagesView] has finished setting up its
  /// handlers AND its list key (both sync and async loadChunk paths).
  ///
  /// [SendAnimation] waits on this before firing a [pendingSend] so that
  /// [handleNewMessage] → [_listKey.currentState?.insertItem] is guaranteed
  /// to find a mounted [SliverAnimatedList], preventing the silent no-op race.
  Completer<void> _messagesViewReady = Completer<void>();

  /// Called by [MessagesView] once its handlers and list key are fully set up.
  void markMessagesViewReady() {
    if (!_messagesViewReady.isCompleted) {
      _messagesViewReady.complete();
    }
  }

  /// Called by [MessagesView.dispose] so that the next visit starts fresh.
  void resetMessagesViewReady() {
    if (_messagesViewReady.isCompleted) {
      _messagesViewReady = Completer<void>();
    }
  }

  /// Future that resolves once [MessagesView] has fully initialized.
  Future<void> get messagesViewReady => _messagesViewReady.future;

  /// Coordinates message list mutations against the in-flight send animation.
  ///
  /// [SendAnimation] holds this for the duration of its flight so that a
  /// message arriving at the same moment can't insert into the list (or toggle
  /// the smart reply / typing indicator rows) and move the animation's landing
  /// target out from under it. Held work replays as soon as the gate opens.
  /// The send itself is never gated — see [MessageListGate].
  final MessageListGate messageListGate = MessageListGate();

  /// A lost stop event would leave the indicator on, so every show re-arms a timeout that hides it.
  void setTypingIndicator(bool display) {
    _typingTimer?.cancel();
    _typingTimer = display ? Timer(const Duration(seconds: 60), () => setTypingIndicator(false)) : null;
    messageListGate.run(() => showTypingIndicator.value = display);
  }

  @override
  void onInit() {
    super.onInit();

    textController.mentionables = mentionables;
    textController.formattingAllowed = () => canFormatText;
    Logger.debug('Created composer for ${chat.guid} ($composerIds)', tag: 'Composer');
    _keyboardSub = KeyboardVisibilityController().onChange.listen((bool visible) async {
      keyboardOpen = visible;
      if (scrollController.hasClients && scrollController.positions.length == 1) {
        _keyboardOffset = scrollController.offset;
      }
    });

    _newMessageSub = EventDispatcherSvc.stream.listen((event) {
      if (event.type != 'new-message' || event.data['chatGuid'] != chat.guid) return;
      if ((event.data['message'] as Message).isFromMe != true) setTypingIndicator(false);
    });

    scrollController.addListener(() {
      if (!scrollController.hasClients || scrollController.positions.length != 1) return;
      if (keyboardOpen &&
          SettingsSvc.settings.hideKeyboardOnScroll.value &&
          scrollController.offset > _keyboardOffset + 100) {
        focusNode.unfocus();
        subjectFocusNode.unfocus();
      }

      if (showScrollDown.value && scrollController.offset >= 500) return;
      if (!showScrollDown.value && scrollController.offset < 500) return;

      if (scrollController.offset >= 500 && !showScrollDown.value) {
        showScrollDown.value = true;
        if (_scrollDownDebounce?.isActive ?? false) _scrollDownDebounce?.cancel();
        _scrollDownDebounce = Timer(const Duration(seconds: 3), () {
          showScrollDown.value = false;
        });
      } else if (showScrollDown.value) {
        showScrollDown.value = false;
      }
    });

    focusNode.addListener(() {
      if (focusNode.hasFocus) {
        _subjectWasLastFocused = false;
      }
    });

    subjectFocusNode.addListener(() {
      if (subjectFocusNode.hasFocus) {
        _subjectWasLastFocused = true;
      }
    });
  }

  @override
  void onClose() {
    _keyboardSub?.cancel();
    _typingTimer?.cancel();
    _newMessageSub?.cancel();
    _scrollDownDebounce?.cancel();
    messageListGate.dispose();
    updatePillRowLayout(visible: false, height: 0);
    for (PlayerController a in audioPlayers.values) {
      a.pausePlayer();
      a.dispose();
    }
    for (Player a in audioPlayersDesktop.values) {
      a.dispose();
    }
    for (VideoController a in videoPlayers.values) {
      a.player.pause();
      a.player.dispose();
    }
    final entries = editing.toList();
    editing.clear();
    _disposeEditEntriesAfterFrame(entries);
    super.onClose();
  }

  void disposeComposer() {
    if (_composerDisposed) return;
    scrollController.dispose();
    focusNode.dispose();
    subjectFocusNode.dispose();
    textController.dispose();
    subjectTextController.dispose();
    _composerDisposed = true;
    Logger.debug('Disposed composer for ${chat.guid} ($composerIds)', tag: 'Composer');
  }

  /// Disposes and evicts the cached [VideoController] for [attachmentGuid] -- call before a
  /// redownload replaces the underlying file, since the cached controller/aspect ratio is from
  /// the old decode and would otherwise get reused as-is.
  void invalidateVideoPlayer(String attachmentGuid) {
    final controller = videoPlayers.remove(attachmentGuid);
    if (controller == null) return;
    controller.player.pause();
    controller.player.dispose();
  }

  /// Disposes every cached inline video player and returns how many were released.
  ///
  /// Called by the cache service when the app is backgrounded or memory is low. A
  /// `VideoPlayer` widget still holding one of these listens for the
  /// `video-players-evicted` event and falls back to its thumbnail.
  int disposeVideoPlayers() {
    final released = videoPlayers.length;
    for (final controller in videoPlayers.values) {
      controller.player.pause();
      controller.player.dispose();
    }
    videoPlayers.clear();
    return released;
  }

  Future<void> scrollToBottom() async {
    if (scrollController.positions.isNotEmpty && scrollController.positions.first.extentBefore > 0) {
      final position = scrollController.positions.first;
      // A fixed-duration animation over many screens is a blur; skip most of the distance first.
      if (position.extentBefore > position.viewportDimension * 2) {
        scrollController.jumpTo(position.viewportDimension);
      }
      await scrollController.animateTo(
        0.0,
        curve: Curves.easeOut,
        duration: const Duration(milliseconds: 300),
      );
    }

    if (SettingsSvc.settings.openKeyboardOnSTB.value) {
      focusNode.requestFocus();
    }
  }

  Future<void> send(SendData data) async {
    await sendFunc?.call(data);
  }

  bool isSelected(String guid) {
    return selected.firstWhereOrNull((e) => e.guid == guid) != null;
  }

  bool isEditing(String guid, int part) {
    return editing.firstWhereOrNull((e) => e.message.guid == guid && e.part.part == part) != null;
  }

  void endEdit(String guid, int part) {
    final removed = editing.where((e) => e.message.guid == guid && e.part.part == part).toList();
    editing.removeWhere(removed.contains);
    _disposeEditEntriesAfterFrame(removed);
  }

  void _disposeEditEntriesAfterFrame(List<MessageEditEntry> entries) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final e in entries) {
        e.controller.focusNode?.dispose();
        e.controller.dispose();
      }
    });
  }

  void updatePillRowLayout({required bool visible, required double height, bool hasQuickActions = false}) {
    pillRowHasQuickActions = visible && hasQuickActions;
    if (showPillRow.value != visible) {
      showPillRow.value = visible;
    }

    final nextHeight = visible ? height : 0.0;
    if (pillRowHeight.value != nextHeight) {
      pillRowHeight.value = nextHeight;
    }
  }

  void close() {
    updatePillRowLayout(visible: false, height: 0);
    ChatsSvc.setAllInactiveSync();
    deleteIfCurrent();
  }

  /// Deletes this controller unless a newer one for the same chat has taken over its tag.
  void deleteIfCurrent() {
    if (Get.isRegistered<ConversationViewController>(tag: tag) &&
        identical(Get.find<ConversationViewController>(tag: tag), this)) {
      Get.delete<ConversationViewController>(tag: tag, force: true);
    }
  }

  Future<void> saveReplyToMessageState() async {
    await PrefsInterface.saveReplyToMessageState(
      chat.guid,
      replyToMessage?.message.guid,
      replyToMessage?.partIndex,
    );
  }

  Future<void> loadReplyToMessageState() async {
    final data = await PrefsInterface.loadReplyToMessageState(chat.guid);
    if (data != null) {
      final messageGuid = data['messageGuid'] as String;
      final messagePart = data['messagePart'] as int;
      final message = Message.findOne(guid: messageGuid);
      if (message != null && !_isAnsweredEmptyReply(message)) {
        replyToMessage = MessageReplyContext(message, messagePart);
      }
    }
  }

  // A reply sent from another device never clears the reply saved here. Typed text means a new reply is in progress.
  bool _isAnsweredEmptyReply(Message target) {
    final draft = ChatsSvc.getChatState(chat.guid)?.textFieldText.value ?? chat.textFieldText;
    if (draft?.trim().isNotEmpty ?? false) return false;
    final query = Database.messages
        .query(Message_.threadOriginatorGuid
            .equals(target.threadOriginatorGuid ?? target.guid!)
            .and(Message_.isFromMe.equals(true)))
        .build();
    final answered = query.count() > 0;
    query.close();
    return answered;
  }
}
