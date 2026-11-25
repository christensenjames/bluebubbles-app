import 'package:animations/animations.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/audio_player.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/collections/media_collection.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/contact_card.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/image_viewer.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/other_file.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/video_player.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/url_preview.dart';
import 'package:bluebubbles/app/state/attachment_state_scope.dart';
import 'package:bluebubbles/app/state/chat_state_scope.dart';
import 'package:bluebubbles/app/state/message_state_scope.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/conversation_fullscreen_holder.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/viewer_chrome.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/ui/theme_helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:passkit_ui/passkit_ui.dart';

/// Fully resolved attachment: dispatches to the appropriate viewer widget.
/// No reactive state is needed here — the file is static once this is shown.
class ResolvedFileContent extends StatelessWidget {
  const ResolvedFileContent({
    super.key,
    required this.file,
    required this.audioTranscript,
    required this.showTail,
    required this.isiOS,
    required this.cvController,
    this.isInReply = false,
    this.forceAllCornersRounded = false,
    this.fill = false,
  });

  final PlatformFile file;
  final String? audioTranscript;
  final bool showTail;
  final bool isiOS;
  final ConversationViewController? cvController;
  final bool isInReply;
  final bool forceAllCornersRounded;

  /// Cover-fill a parent-fixed frame (collection cards).
  final bool fill;

  /// Bubble-style media radius, or zero when [fill] (parent owns clip/shadow).
  BorderRadius _mediaBorderRadius(Message message) {
    if (fill) return BorderRadius.zero;
    if (isiOS) {
      return BorderRadius.only(
        topLeft: const Radius.circular(20.0),
        topRight: const Radius.circular(20.0),
        bottomLeft: forceAllCornersRounded
            ? const Radius.circular(20.0)
            : (message.isFromMe! ? const Radius.circular(20.0) : Radius.zero),
        bottomRight: forceAllCornersRounded
            ? const Radius.circular(20.0)
            : (!message.isFromMe! ? const Radius.circular(20.0) : Radius.zero),
      );
    }
    return const BorderRadius.all(Radius.circular(5.0));
  }

  @override
  Widget build(BuildContext context) {
    final message = MessageStateScope.messageOf(context);
    final attachment = AttachmentStateScope.attachmentOf(context);
    final currentChat = ChatStateScope.maybeChatOf(context);
    final mediaRadius = context.material && !fill ? BorderRadius.zero : _mediaBorderRadius(message);
    final tailPadding = context.material
        ? EdgeInsets.zero
        : EdgeInsets.only(
            left: message.isFromMe! ? 0 : 10,
            right: message.isFromMe! ? 10 : 0,
          );
    if (attachment.mimeStart == "image" && !SettingsSvc.settings.highPerfMode.value) {
      final collection = MediaCollectionScope.maybeOf(context);
      final image = ImageViewer(
        file: file,
        attachment: attachment,
        isFromMe: message.isFromMe!,
        isInReply: isInReply,
        controller: cvController,
        fill: fill,
      );
      if (context.material && !fill) {
        return _HeroImageBubble(
          attachment: attachment,
          currentChat: currentChat,
          cvController: cvController,
          galleryAttachments: collection?.media,
          child: image,
        );
      }
      return OpenContainer(
        tappable: false,
        openColor: Colors.black,
        closedColor: Colors.transparent,
        closedElevation: 0,
        closedShape: RoundedRectangleBorder(borderRadius: mediaRadius),
        useRootNavigator: false,
        openBuilder: (context, _) => ConversationFullscreenHolder(
          currentChat: currentChat,
          attachment: attachment,
          showInteractions: true,
          galleryAttachments: collection?.media,
          onOpenCollectionGallery: collection?.openGallery,
        ),
        closedBuilder: (context, openContainer) => GestureDetector(
          onTap: () {
            final ctrl = cvController ?? cvc(currentChat!);
            ctrl.focusNode.unfocus();
            ctrl.subjectFocusNode.unfocus();
            openContainer();
          },
          // ImageViewer expands itself in fill mode; the transparent box keeps the tap target opaque.
          child: Container(color: Colors.transparent, child: image),
        ),
      );
    }

    if (attachment.mimeStart == "video" && !SettingsSvc.settings.highPerfMode.value) {
      final video = VideoPlayer(
        attachment: attachment,
        file: file,
        controller: cvController,
        isFromMe: message.isFromMe!,
        fill: fill,
      );
      // VideoPlayer expands itself in fill mode.
      return ClipRRect(borderRadius: mediaRadius, child: video);
    }

    if (attachment.mimeStart == "audio") {
      return Padding(
        padding: showTail ? tailPadding : EdgeInsets.zero,
        child: AudioPlayer(
          // The quoted copy in a reply bubble is height-capped; the transcript would overflow it
          transcript: isInReply ? null : audioTranscript,
          attachment: attachment,
          file: file,
          controller: cvController,
        ),
      );
    }

    if (attachment.mimeType == "text/x-vlocation" || attachment.uti == 'public.vlocation') {
      return Padding(
        padding: showTail ? tailPadding : EdgeInsets.zero,
        child: UrlPreview(
          data: UrlPreviewData(
            title: "Location from ${DateFormat.yMd().format(message.dateCreated!.toLocal())}",
            siteName: "Tap to open",
          ),
          file: file,
        ),
      );
    }

    if (attachment.mimeType?.contains("vcard") ?? false) {
      return Padding(
        padding: showTail ? tailPadding : EdgeInsets.zero,
        child: ContactCard(attachment: attachment, file: file),
      );
    }

    if (attachment.isPkPass) {
      return Padding(
        padding: showTail ? tailPadding : EdgeInsets.zero,
        child: FittedBox(fit: BoxFit.contain, child: PkPassWidget(pass: attachment.pkPass!)),
      );
    }

    return Padding(
      padding: showTail ? tailPadding : EdgeInsets.zero,
      child: OtherFile(attachment: attachment, file: file),
    );
  }
}

class _HeroImageBubble extends StatefulWidget {
  const _HeroImageBubble({
    required this.attachment,
    required this.currentChat,
    required this.cvController,
    required this.galleryAttachments,
    required this.child,
  });

  final Attachment attachment;
  final Chat? currentChat;
  final ConversationViewController? cvController;
  final List<Attachment>? galleryAttachments;
  final Widget child;

  @override
  State<_HeroImageBubble> createState() => _HeroImageBubbleState();
}

class _HeroImageBubbleState extends State<_HeroImageBubble> {
  // The Hero is only live while this bubble's viewer is open, so duplicate tags never coexist in the chat route.
  bool _opened = false;

  void _open() {
    final ctrl = widget.cvController ?? cvc(widget.currentChat!);
    ctrl.focusNode.unfocus();
    ctrl.subjectFocusNode.unfocus();
    final route = ThemeSwitcher.buildTransparentPageRoute<void>(
      builder: (_) => ConversationFullscreenHolder(
        currentChat: widget.currentChat,
        attachment: widget.attachment,
        showInteractions: true,
        galleryAttachments: widget.galleryAttachments,
      ),
    );
    setState(() => _opened = true);
    Navigator.of(context).push(route);
    route.completed.whenComplete(() {
      if (mounted) setState(() => _opened = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Both flights carry the viewer's decoded image; the bubble image stays mounted outside the Hero, so no spinner.
    return GestureDetector(
      onTap: _open,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: HeroMode(
              enabled: _opened,
              child: Hero(
                tag: ConversationFullscreenHolder.heroTagFor(widget.attachment),
                createRectTween: viewerHeroRectTween,
                flightShuttleBuilder: (_, _, direction, fromContext, toContext) =>
                    ((direction == HeroFlightDirection.push ? toContext : fromContext).widget as Hero).child,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
