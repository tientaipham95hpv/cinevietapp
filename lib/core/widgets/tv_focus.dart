import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/cineviet_colors.dart';
import '../theme/cineviet_dimensions.dart';

class TvFocus extends StatefulWidget {
  const TvFocus({
    super.key,
    required this.child,
    this.borderRadius,
    this.scale = 1.035,
    this.padding = EdgeInsets.zero,
    this.onTap,
    this.focusNode,
    this.enabled = true,
    this.builder,
    this.autofocus = false,
    this.onKeyEvent,
    this.ensureVisibleAlignment = 0.5,
    this.autoEnsureVisible = true,
    this.onFocusChanged,
    this.ensureParentScrollable = true,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final double scale;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final FocusNode? focusNode;
  final bool enabled;
  final bool autofocus;
  final FocusOnKeyEventCallback? onKeyEvent;
  final double ensureVisibleAlignment;
  final bool autoEnsureVisible;
  final ValueChanged<bool>? onFocusChanged;
  final bool ensureParentScrollable;
  final Widget Function(BuildContext context, bool focused, Widget child)?
  builder;

  @override
  State<TvFocus> createState() => _TvFocusState();
}

class _TvFocusState extends State<TvFocus> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final radius =
        widget.borderRadius ?? BorderRadius.circular(CineVietRadius.lg);
    final focused = widget.enabled && _focused;
    final decorated = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: focused ? CineVietColors.cardHover : null,
        borderRadius: radius,
        border: focused
            ? Border.all(color: CineVietColors.accent, width: 2)
            : null,
        boxShadow: focused
            ? const [
                BoxShadow(
                  color: CineVietColors.accentGlow,
                  blurRadius: 24,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      transform: Matrix4.identity()
        ..scaleByDouble(
          focused ? widget.scale : 1.0,
          focused ? widget.scale : 1.0,
          1,
          1,
        ),
      transformAlignment: Alignment.center,
      child:
          widget.builder?.call(context, focused, widget.child) ?? widget.child,
    );

    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onKeyEvent: (node, event) {
        final customResult = widget.onKeyEvent?.call(node, event);
        if (customResult == KeyEventResult.handled) {
          return KeyEventResult.handled;
        }
        if (!widget.enabled || widget.onTap == null || event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          widget.onTap!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      onFocusChange: (value) {
        setState(() => _focused = value);
        widget.onFocusChanged?.call(value);
        // TV/keyboard focus moved here: bring this item into view by scrolling
        // every enclosing Scrollable (vertical page + horizontal rail). This
        // replaces the old global key-scroll hack and never scrolls when focus
        // is elsewhere (e.g. sidebar), so picking a menu no longer drags home.
        if (value && widget.enabled && widget.autoEnsureVisible) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final ctx = context;
            if (!ctx.mounted) return;
            Scrollable.ensureVisible(
              ctx,
              alignment: widget.ensureVisibleAlignment,
              alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
            );
            if (widget.ensureParentScrollable) {
              final parentScrollable = Scrollable.maybeOf(ctx);
              if (parentScrollable != null && parentScrollable.context.mounted) {
                Scrollable.ensureVisible(
                  parentScrollable.context,
                  alignment: 0.3,
                  alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                );
              }
            }
          });
        }
      },
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          // TvFocus's own Focus node owns D-pad/keyboard focus and key
          // handling. The inner InkWell must NOT also request focus, otherwise
          // every TvFocus exposes two focus stops which traps directional
          // navigation and makes some controls (e.g. the search button) feel
          // unresponsive on Android TV.
          canRequestFocus: false,
          borderRadius: radius,
          focusColor: Colors.transparent,
          hoverColor: CineVietColors.accentSoft,
          onTap: widget.onTap,
          child: decorated,
        ),
      ),
    );
  }
}
