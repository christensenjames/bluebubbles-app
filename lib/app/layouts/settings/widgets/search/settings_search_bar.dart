import 'dart:async';

import 'package:bluebubbles/app/layouts/settings/widgets/search/settings_search_bar_ios.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:gesture_x_detector/gesture_x_detector.dart';

class SettingsSearchBar extends StatefulWidget {
  final ValueChanged<String>? onChanged;
  final bool iOS;
  final bool material;
  final bool showBack;
  final Color? tileColor;

  const SettingsSearchBar({
    super.key,
    this.onChanged,
    required this.iOS,
    required this.material,
    this.showBack = false,
    this.tileColor,
  });

  @override
  State<SettingsSearchBar> createState() => _SettingsSearchBarState();
}

class _SettingsSearchBarState extends State<SettingsSearchBar> {
  String searchValue = '';
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounceTimer;

  void _onSearchChanged(String query) {
    setState(() {
      searchValue = query.toLowerCase();
    });

    _debounceTimer?.cancel();

    if (query.trim().length < 3) {
      widget.onChanged?.call('');
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      widget.onChanged?.call(searchValue);
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<Widget> get _trailing => <Widget>[
        if (searchValue.isNotEmpty)
          Tooltip(
            message: 'Clear search',
            child: IconButton(
              onPressed: () {
                _debounceTimer?.cancel();
                setState(() {
                  searchValue = '';
                  _controller.text = '';
                  _focusNode.unfocus();
                });
                widget.onChanged?.call('');
              },
              icon: const Icon(Icons.clear),
            ),
          ),
      ];

  void _goBack(BuildContext context) {
    if (Get.isSnackbarOpen) {
      Get.closeAllSnackbars();
    }
    Navigator.of(context).pop();
  }

  Widget _buildMaterialPill(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textStyle = Theme.of(context).textTheme.bodyLarge!.copyWith(fontSize: 20);
    return SearchBar(
      controller: _controller,
      focusNode: _focusNode,
      hintText: 'Search Settings',
      hintStyle: WidgetStatePropertyAll(textStyle.copyWith(color: colors.onSurfaceVariant)),
      textStyle: WidgetStatePropertyAll(textStyle.copyWith(color: colors.onSurface)),
      constraints: const BoxConstraints(minHeight: 72),
      backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerLowest),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      shape: WidgetStatePropertyAll(StadiumBorder(side: BorderSide(color: colors.outlineVariant))),
      padding: WidgetStatePropertyAll<EdgeInsets>(EdgeInsets.fromLTRB(widget.showBack ? 12 : 24, 0, 24, 0)),
      onChanged: _onSearchChanged,
      leading: widget.showBack
          ? XGestureDetector(
              supportTouch: true,
              onTap: kIsDesktop ? (_) => _goBack(context) : null,
              child: IconButton(
                icon: Icon(Icons.arrow_back, color: colors.onSurfaceVariant),
                tooltip: 'Back',
                onPressed: () {
                  if (!kIsDesktop) _goBack(context);
                },
              ),
            )
          : Icon(Icons.search, color: colors.onSurfaceVariant),
      trailing: _trailing,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.material) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: _buildMaterialPill(context),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: widget.iOS
          ? SettingsSearchBariOS(
              // use cupertino search bar if iOS style
              controller: _controller,
              focusNode: _focusNode,
              onChanged: _onSearchChanged,
            )
          : SearchBar(
              // material themed search bar
              controller: _controller,
              focusNode: _focusNode,
              backgroundColor: widget.tileColor != null ? WidgetStatePropertyAll(widget.tileColor) : null,
              hintText: 'Search Settings',
              hintStyle: WidgetStateProperty.all(
                TextStyle(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withValues(alpha: 0.5)
                      : Colors.black.withValues(alpha: 0.5),
                ),
              ),
              padding: const WidgetStatePropertyAll<EdgeInsets>(
                EdgeInsets.symmetric(horizontal: 16.0),
              ),
              elevation: const WidgetStatePropertyAll(1),
              onChanged: _onSearchChanged,
              leading: const Icon(Icons.search),
              trailing: _trailing,
            ),
    );
  }
}
