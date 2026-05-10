import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A text field tailored for Android TV remote control input.
///
/// Behaviour:
///   * The OUTER wrapper receives D-Pad focus (visible border / glow).
///   * Pressing OK / ENTER while the outer wrapper is focused transfers
///     focus to an inner hidden `TextFormField`, which opens the TV's
///     built-in on-screen (IME) keyboard.
///   * While the inner text field is active, pressing D-Pad UP or DOWN
///     exits the field and moves focus to the next traversable widget in
///     that direction. LEFT / RIGHT are left to the text field so the
///     user can still move the caret inside the text.
///   * BACK / ESC releases focus and hides the keyboard, returning to the
///     outer focus ring so the user can keep navigating with the D-Pad.
class TvTextField extends StatefulWidget {
  final TextEditingController? controller;
  final String? hintText;
  final String? labelText;
  final Widget? prefixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final FormFieldSetter<String>? onSaved;
  final String? initialValue;

  const TvTextField({
    super.key,
    this.controller,
    this.hintText,
    this.labelText,
    this.prefixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.validator,
    this.onSaved,
    this.initialValue,
  });

  @override
  State<TvTextField> createState() => _TvTextFieldState();
}

class _TvTextFieldState extends State<TvTextField> {
  final FocusNode _outerFocus = FocusNode(debugLabel: 'TvTextField.outer');
  // skipTraversal keeps this node out of D-Pad traversal; it is reached only
  // via explicit requestFocus() when the user presses OK on the wrapper.
  final FocusNode _innerFocus = FocusNode(
    debugLabel: 'TvTextField.inner',
    skipTraversal: true,
  );

  @override
  void initState() {
    super.initState();
    _outerFocus.addListener(_onFocusChanged);
    _innerFocus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _outerFocus.removeListener(_onFocusChanged);
    _innerFocus.removeListener(_onFocusChanged);
    _outerFocus.dispose();
    _innerFocus.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  /// Outer focus key handling: OK / Enter activates the inner text field.
  KeyEventResult _outerOnKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.gameButtonA) {
      _innerFocus.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Inner focus key handling: UP / DOWN exit the field, BACK cancels.
  KeyEventResult _innerOnKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _outerFocus.requestFocus();
      // Use the global FocusManager to traverse from the now-focused outer.
      FocusManager.instance.primaryFocus
          ?.focusInDirection(TraversalDirection.up);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _outerFocus.requestFocus();
      FocusManager.instance.primaryFocus
          ?.focusInDirection(TraversalDirection.down);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      _outerFocus.requestFocus();
      return KeyEventResult.handled;
    }
    // LEFT / RIGHT remain handled by the TextField itself for caret movement.
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focusColor = theme.colorScheme.primary;
    final isFocused = _outerFocus.hasFocus || _innerFocus.hasFocus;
    final isEditing = _innerFocus.hasFocus;

    return Focus(
      focusNode: _outerFocus,
      autofocus: widget.autofocus,
      onKeyEvent: _outerOnKey,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isFocused ? focusColor : Colors.transparent,
            width: 3,
          ),
          boxShadow: isFocused
              ? [
                  BoxShadow(
                    color: focusColor.withAlpha(140),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Focus(
          // Second Focus solely so the inner field receives our key handler
          // without exposing another traversal stop.
          onKeyEvent: _innerOnKey,
          child: TextFormField(
            controller: widget.controller,
            initialValue: widget.controller == null ? widget.initialValue : null,
            focusNode: _innerFocus,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            onChanged: widget.onChanged,
            onFieldSubmitted: (value) {
              widget.onSubmitted?.call(value);
              // After Enter on the IME keyboard, kick focus back to the
              // outer ring so the user can D-Pad onwards.
              _innerFocus.unfocus();
              _outerFocus.requestFocus();
            },
            validator: widget.validator,
            onSaved: widget.onSaved,
            // Tapping outside the field (mouse / remote with trackpad)
            // closes the keyboard cleanly.
            onTapOutside: (_) {
              if (_innerFocus.hasFocus) _innerFocus.unfocus();
            },
            decoration: InputDecoration(
              hintText: widget.hintText,
              labelText: widget.labelText,
              prefixIcon: widget.prefixIcon,
              suffixIcon: isEditing
                  ? const Icon(Icons.keyboard_alt_outlined)
                  : null,
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide.none,
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide.none,
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(10)),
                borderSide: BorderSide.none,
              ),
              filled: false,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
