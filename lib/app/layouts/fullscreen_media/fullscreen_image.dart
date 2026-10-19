import 'dart:async';

import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/attachment/live_photo_mixin.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/dialogs/metadata_dialog.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/viewer_chrome.dart';
import 'package:bluebubbles/app/layouts/fullscreen_media/zoomable_media.dart';
import 'package:bluebubbles/utils/share.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/backend/interfaces/image_interface.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart' as intl;
import 'package:photo_view/photo_view.dart';
import 'dart:io';

class FullscreenImage extends StatefulWidget {
  const FullscreenImage({
    super.key,
    required this.file,
    required this.attachment,
    required this.showInteractions,
    required this.updatePhysics,
    this.onOverlayToggle,
    this.onTap,
    this.onDismissProgress,
    this.onDismiss,
    this.heroTag,
  });

  final PlatformFile file;
  final Attachment attachment;
  final bool showInteractions;
  final Function(ScrollPhysics) updatePhysics;
  final Function(bool)? onOverlayToggle;

  /// Non-null when the holder draws the shared chrome, so the page draws no bars of its own.
  final VoidCallback? onTap;
  final ValueChanged<double>? onDismissProgress;
  final VoidCallback? onDismiss;
  final String? heroTag;

  @override
  State<FullscreenImage> createState() => _FullscreenImageState();
}

class _FullscreenImageState extends State<FullscreenImage>
    with AutomaticKeepAliveClientMixin, LivePhotoMixin, ThemeHelpers
    implements ViewerPageActions {
  final PhotoViewController controller = PhotoViewController();
  bool showOverlay = true;
  bool hasError = false;
  Uint8List? bytes;
  String? compatiblePath; // For converted HEIC/TIFF files
  // Decoding the original only once the user zooms keeps a 24 MP photo (~100 MB decoded) from
  // flushing every chat thumbnail out of the shared 100 MB imageCache.
  bool _fullResolution = false;
  bool _fullResolutionRequested = false;
  late PlatformFile _currentFile;
  Worker? _resolvedFileWorker;

  PlatformFile get file => _currentFile;
  Attachment get attachment => widget.attachment;
  Message? get message => attachment.message.target;

  // Implement required getter for LivePhotoMixin
  @override
  Attachment get livePhotoAttachment => attachment;

  @override
  void initState() {
    super.initState();
    _currentFile = widget.file;
    compatiblePath = _readyCompatiblePath(_currentFile);
    if (!_sharedChrome) _setFullscreen(true);
    _watchAttachmentFile();
    initBytes();
  }

  @override
  void didUpdateWidget(covariant FullscreenImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The holder builds a fresh PlatformFile on every rebuild (each zoom-state change triggers one),
    // so identity would remount PhotoView mid-zoom against the controller's stale scale/position.
    final changed = widget.file.path == null
        ? !identical(oldWidget.file, widget.file)
        : oldWidget.file.path != widget.file.path;
    if (changed) _replaceFile(widget.file);
  }

  void _watchAttachmentFile() {
    final currentMessage = message;
    final chatGuid = currentMessage?.chat.target?.guid;
    final messageGuid = currentMessage?.guid;
    final attachmentGuid = attachment.guid;
    if (chatGuid == null || messageGuid == null || attachmentGuid == null) return;
    final state = maybeFindMessagesSvc(chatGuid)?.getAttachmentState(messageGuid, attachmentGuid);
    if (state == null) return;
    _resolvedFileWorker = ever(state.resolvedFile, (PlatformFile? updatedFile) {
      if (updatedFile != null) _replaceFile(updatedFile);
    });
  }

  void _replaceFile(PlatformFile updatedFile) {
    if (identical(_currentFile, updatedFile)) return;
    setState(() {
      _currentFile = updatedFile;
      bytes = null;
      compatiblePath = _readyCompatiblePath(updatedFile);
      hasError = false;
    });
    unawaited(initBytes());
  }

  String? _readyCompatiblePath(PlatformFile f) =>
      kIsWeb || f.path == null ? null : AttachmentsSvc.readyCompatiblePath(attachment, actualPath: f.path);

  void _setFullscreen(bool fullscreen) {
    if (fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> initBytes() async {
    // For web, we need bytes in memory
    if (kIsWeb || file.path == null) {
      if (attachment.mimeType?.contains("image/tif") ?? false) {
        bytes = await ImageInterface.convertToPng(file);
      } else {
        bytes = file.bytes;
      }
      if (mounted) setState(() {});
      return;
    }

    // For non-web platforms, ensure we have a compatible image path
    // but don't load bytes into memory - let Image.file handle it
    compatiblePath = await AttachmentsSvc.ensureImageCompatibility(attachment, actualPath: file.path!);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (!_sharedChrome) _setFullscreen(false);
    _resolvedFileWorker?.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  void refreshAttachment() {
    setState(() {
      bytes = null;
      compatiblePath = null;
      hasError = false;
    });
    void onComplete(PlatformFile newFile) {
      if (!mounted) return;
      if (kIsWeb || newFile.path == null) {
        setState(() {
          bytes = newFile.bytes;
        });
      } else {
        initBytes();
      }
    }

    void onError() {
      if (!mounted) return;
      setState(() {
        hasError = true;
      });
    }

    redownloadAttachmentFromViewer(attachment, onComplete: onComplete, onError: onError);
  }

  @override
  void download() => AttachmentsSvc.saveToDisk(file);

  @override
  void shareFile() {
    if (file.path != null) Share.files([file.path!]);
  }

  @override
  VoidCallback? get enterPip => null;

  bool get _sharedChrome => widget.onTap != null;

  void _onScaleStateChanged(PhotoViewScaleState scale) {
    final zoomed =
        scale == PhotoViewScaleState.zoomedIn ||
        scale == PhotoViewScaleState.covering ||
        scale == PhotoViewScaleState.originalSize;
    widget.updatePhysics(zoomed ? const NeverScrollableScrollPhysics() : ThemeSwitcher.getScrollPhysics());
    _onZoomChanged(zoomed);
  }

  void _onZoomChanged(bool zoomed) {
    if (zoomed && !_fullResolution && !_fullResolutionRequested && compatiblePath != null) {
      _fullResolutionRequested = true;
      var loadFailed = false;
      // Decoded off-tree: swapping the provider first blanks the screen for the length of the decode.
      precacheImage(
        FileImage(File(compatiblePath!)),
        context,
        onError: (Object error, StackTrace? stackTrace) {
          loadFailed = true;
          _fullResolutionRequested = false;
          Logger.error('Full-res precache failed for ${attachment.guid}', error: error, trace: stackTrace);
        },
      ).then((_) {
        if (mounted && !loadFailed) setState(() => _fullResolution = true);
      });
    }
  }

  void _toggleOverlay() {
    if (!widget.showInteractions) return;
    final newVal = !showOverlay;
    setState(() => showOverlay = newVal);
    widget.onOverlayToggle?.call(newVal);
  }

  Widget _buildPhotoView(BuildContext context) {
    if (bytes == null && compatiblePath == null) {
      return hasError
          ? Center(child: Text("Failed to load image", style: context.theme.textTheme.bodyLarge))
          : Center(child: buildProgressIndicator(context));
    }

    Widget failed(BuildContext context, Object error, StackTrace? stackTrace) {
      Logger.error('Fullscreen image decode failed for ${attachment.guid}', error: error, trace: stackTrace);
      return Center(child: Text("Failed to display image", style: context.theme.textTheme.bodyLarge));
    }

    if (material) return _buildZoomable(failed);

    if (bytes != null) {
      return PhotoView(
        key: ObjectKey(file),
        gaplessPlayback: true,
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.contained * 10,
        controller: controller,
        imageProvider: MemoryImage(bytes!),
        loadingBuilder: (context, _) => Center(child: buildProgressIndicator(context)),
        scaleStateChangedCallback: _onScaleStateChanged,
        errorBuilder: failed,
        filterQuality: FilterQuality.high,
      );
    }

    final original = FileImage(File(compatiblePath!));
    final screenSized = _screenSized(original);

    // No orientation handling here: the decoder applies EXIF orientation
    // itself, so the provider's reported size is already display-space and
    // PhotoViewComputedScale.contained reads it correctly.
    final width = attachment.displayWidth, height = attachment.displayHeight;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return PhotoView(
        key: ObjectKey(file),
        gaplessPlayback: true,
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.contained * 10,
        controller: controller,
        imageProvider: screenSized,
        loadingBuilder: (context, _) => Center(child: buildProgressIndicator(context)),
        scaleStateChangedCallback: _onScaleStateChanged,
        errorBuilder: failed,
        filterQuality: FilterQuality.high,
      );
    }

    // A fixed childSize keeps PhotoView's geometry identical when the image underneath
    // swaps from the screen-sized decode to the original.
    return PhotoView.customChild(
      key: ObjectKey(file),
      childSize: Size(width.toDouble(), height.toDouble()),
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.contained * 10,
      controller: controller,
      scaleStateChangedCallback: _onScaleStateChanged,
      child: _image(_fullResolution ? original : screenSized, failed),
    );
  }

  ImageProvider _screenSized(ImageProvider original) {
    // Desktop uses the display, not the window, so a drag-resize doesn't re-decode every frame.
    final display = View.of(context).display.size;
    final screen = kIsDesktop && !display.isEmpty
        ? display
        : MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
    return ResizeImage(
      original,
      width: screen.width.ceil(),
      height: screen.height.ceil(),
      policy: ResizeImagePolicy.fit,
    );
  }

  // Image resets `frame` to null on a provider change; gaplessPlayback keeps painting the
  // screen-sized frame meanwhile, so only the first load may show the spinner.
  Widget _image(ImageProvider provider, ImageErrorWidgetBuilder failed) => Image(
    image: provider,
    gaplessPlayback: true,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.high,
    frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
        wasSynchronouslyLoaded || frame != null || _fullResolution
        ? child
        : Center(child: buildProgressIndicator(context)),
    errorBuilder: failed,
  );

  Widget _buildZoomable(ImageErrorWidgetBuilder failed) {
    // The decoder applies EXIF orientation itself, so the attachment's display size is already display-space.
    final width = attachment.displayWidth, height = attachment.displayHeight;
    final hasSize = width != null && height != null && width > 0 && height > 0;
    final ImageProvider provider;
    if (bytes != null) {
      provider = MemoryImage(bytes!);
    } else {
      final original = FileImage(File(compatiblePath!));
      // Without known dimensions the size comes from the decoded image, so swapping to the original would rescale.
      provider = _fullResolution && hasSize ? original : _screenSized(original);
    }
    Widget zoomable(Size size) => ZoomableMedia(
      key: ObjectKey(file),
      childSize: size,
      onTap: widget.onTap ?? _toggleOverlay,
      onZoomChanged: _onZoomChanged,
      onDismissProgress: widget.onDismissProgress,
      onDismiss: widget.onDismiss,
      child: _hero(_image(provider, failed)),
    );
    if (hasSize) return zoomable(Size(width.toDouble(), height.toDouble()));
    return _ImageSizeBuilder(provider: provider, errorBuilder: failed, builder: zoomable);
  }

  Widget _hero(Widget child) =>
      widget.heroTag == null ? child : Hero(tag: widget.heroTag!, createRectTween: viewerHeroRectTween, child: child);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Container(
      color: _sharedChrome ? null : Colors.black,
      child: GestureDetector(
        onTap: material ? null : _toggleOverlay,
        onLongPress: () {
          if (attachment.hasLivePhoto && !isDownloadingLivePhoto.value) {
            handleLivePhotoTap();
          }
        },
        child: Stack(
          children: [
            _buildPhotoView(context),
            // Live photo video overlay
            if (attachment.hasLivePhoto) buildLivePhotoOverlay(),
            if (!iOS && !_sharedChrome)
              AnimatedOpacity(
                opacity: showOverlay ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 125),
                child: Container(
                  height: kIsDesktop ? 80 : 100.0,
                  width: NavigationSvc.width(context),
                  color: context.theme.colorScheme.shadow.withValues(alpha: samsung ? 1 : 0.65),
                  child: SafeArea(
                    left: false,
                    right: false,
                    bottom: false,
                    child: SizedBox(
                      height: kIsDesktop ? 80 : 50,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(left: 5),
                                child: CupertinoButton(
                                  padding: const EdgeInsets.symmetric(horizontal: 5),
                                  onPressed: () async {
                                    Navigator.of(context).pop();
                                  },
                                  child: const Icon(Icons.close, color: Colors.white),
                                ),
                              ),
                              if (widget.showInteractions)
                                Padding(
                                  padding: const EdgeInsets.only(left: 5.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        (message?.isFromMe ?? false)
                                            ? 'You'
                                            : message?.handleRelation.target?.displayName ?? "Unknown",
                                        style: context.theme.textTheme.titleLarge!.copyWith(color: Colors.white),
                                      ),
                                      if (message?.dateCreated != null)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2.0),
                                          child: Text(
                                            samsung
                                                ? '${buildTime(message!.dateCreated!)} '
                                                    '${intl.DateFormat.MMMd().format(message!.dateCreated!)}'
                                                : '${intl.DateFormat('EEE').format(message!.dateCreated!)} '
                                                    '${buildTime(message!.dateCreated!)}',
                                            style: context.theme.textTheme.bodyLarge!.copyWith(
                                              color: samsung ? Colors.grey : Colors.white,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          !widget.showInteractions
                              ? const SizedBox.shrink()
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10.0),
                                      child: CupertinoButton(
                                        padding: const EdgeInsets.symmetric(horizontal: 5),
                                        onPressed: () async {
                                          showMetadataDialog(widget.attachment, context);
                                        },
                                        child: const Icon(Icons.info_outlined, color: Colors.white),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10.0),
                                      child: CupertinoButton(
                                        padding: const EdgeInsets.symmetric(horizontal: 5),
                                        onPressed: () async {
                                          refreshAttachment();
                                        },
                                        child: const Icon(Icons.refresh, color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            // Bottom actions bar (iOS style)
            if (widget.showInteractions && iOS)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  opacity: showOverlay ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: SafeArea(
                    top: false,
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        color: samsung
                            ? Colors.black
                            : context.theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.9),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: Icon(
                              CupertinoIcons.cloud_download,
                              color: samsung ? Colors.white : context.theme.colorScheme.primary,
                            ),
                            onPressed: () => AttachmentsSvc.saveToDisk(widget.file),
                          ),
                          if (!kIsWeb && !kIsDesktop)
                            IconButton(
                              icon: Icon(
                                CupertinoIcons.share,
                                color: samsung ? Colors.white : context.theme.colorScheme.primary,
                              ),
                              onPressed: () {
                                if (widget.file.path != null) {
                                  Share.files([widget.file.path!]);
                                }
                              },
                            ),
                          IconButton(
                            icon: Icon(
                              CupertinoIcons.info,
                              color: samsung ? Colors.white : context.theme.colorScheme.primary,
                            ),
                            onPressed: () => showMetadataDialog(widget.attachment, context),
                          ),
                          IconButton(
                            icon: Icon(
                              CupertinoIcons.refresh,
                              color: samsung ? Colors.white : context.theme.colorScheme.primary,
                            ),
                            onPressed: () => refreshAttachment(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class _ImageSizeBuilder extends StatefulWidget {
  const _ImageSizeBuilder({required this.provider, required this.builder, required this.errorBuilder});

  final ImageProvider provider;
  final Widget Function(Size size) builder;
  final ImageErrorWidgetBuilder errorBuilder;

  @override
  State<_ImageSizeBuilder> createState() => _ImageSizeBuilderState();
}

class _ImageSizeBuilderState extends State<_ImageSizeBuilder> {
  late final ImageStreamListener _listener = ImageStreamListener(_onImage, onError: _onError);
  ImageStream? _stream;
  Size? _size;
  Object? _error;
  StackTrace? _stackTrace;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _ImageSizeBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.provider != widget.provider) _resolve();
  }

  void _resolve() {
    final stream = widget.provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    _error = null;
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final size = Size(info.image.width.toDouble(), info.image.height.toDouble());
    if (size != _size) setState(() => _size = size);
  }

  void _onError(Object error, StackTrace? stackTrace) {
    if (!mounted) return;
    setState(() {
      _error = error;
      _stackTrace = stackTrace;
    });
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) return widget.errorBuilder(context, error, _stackTrace);
    final size = _size;
    return size == null ? Center(child: buildProgressIndicator(context)) : widget.builder(size);
  }
}
