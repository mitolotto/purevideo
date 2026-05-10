import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A reusable widget that gives any child an Android TV style focus visual:
/// scale up, glow/border, and optional background tint. Handles D-Pad OK
/// (Enter / DPAD_CENTER) by invoking [onTap].
///
/// Use this instead of `InkWell` / `GestureDetector` for every clickable
/// element that lives on a TV screen.
class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool autofocus;
  final FocusNode? focusNode;
  final BorderRadius borderRadius;

  /// How much the element grows on focus. 1.0 disables scaling.
  final double focusScale;

  /// If true draws a solid colored border around the element on focus.
  final bool showBorder;

  /// If true adds a soft glow shadow around the element on focus.
  final bool showGlow;

  /// Extra padding applied to the external [AnimatedContainer] so that the
  /// border/glow never clips the child.
  final EdgeInsets padding;

  /// Optional override of the focus ring color. Defaults to the theme's
  /// primary color.
  final Color? focusColor;

  /// Optional override of the background color shown while focused.
  final Color? focusedBackgroundColor;

  /// Background when not focused. Transparent by default.
  final Color backgroundColor;

  const TvFocusable({
    super.key,
    required this.child,
    this.onTap,
    this.autofocus = false,
    this.focusNode,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.focusScale = 1.08,
    this.showBorder = true,
    this.showGlow = true,
    this.padding = EdgeInsets.zero,
    this.focusColor,
    this.focusedBackgroundColor,
    this.backgroundColor = Colors.transparent,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late FocusNode _node;
  bool _ownsNode = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode(debugLabel: 'TvFocusable');
    _ownsNode = widget.focusNode == null;
    _node.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _node.removeListener(_onFocusChanged);
      if (_ownsNode) _node.dispose();
      _node = widget.focusNode ?? FocusNode(debugLabel: 'TvFocusable');
      _ownsNode = widget.focusNode == null;
      _node.addListener(_onFocusChanged);
    }
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (_focused != _node.hasFocus) {
      setState(() => _focused = _node.hasFocus);
    }
  }

  @override
  void dispose() {
    _node.removeListener(_onFocusChanged);
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  void _handleActivate() {
    if (widget.onTap != null) {
      widget.onTap!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focusColor = widget.focusColor ?? theme.colorScheme.primary;
    final focusedBg =
        widget.focusedBackgroundColor ?? focusColor.withAlpha(40);

    return FocusableActionDetector(
      focusNode: _node,
      autofocus: widget.autofocus,
      mouseCursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      shortcuts: const <ShortcutActivator, Intent>{
        // Android TV "OK" on most remotes is DPAD_CENTER which Flutter maps
        // to LogicalKeyboardKey.select. Some devices also emit Enter.
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _handleActivate();
            return null;
          },
        ),
      },
      child: GestureDetector(
        // Touchscreen is disabled on the target device, but a mouse is useful
        // when running the app in an emulator / desktop preview.
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _focused ? widget.focusScale : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: widget.padding,
            decoration: BoxDecoration(
              color: _focused ? focusedBg : widget.backgroundColor,
              borderRadius: widget.borderRadius,
              border: widget.showBorder
                  ? Border.all(
                      color: _focused ? focusColor : Colors.transparent,
                      width: 3,
                    )
                  : null,
              boxShadow: _focused && widget.showGlow
                  ? [
                      BoxShadow(
                        color: focusColor.withAlpha(140),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
