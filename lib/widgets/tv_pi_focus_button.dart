import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:amiapp/helpers/tv_util.dart';

/// ラズパイ版メニュー用。角丸は幅の 5%、フォーカス背景は #0099FF。
/// TCLアミの TvFocusable（水色枠）は使わない。
class TvPiFocusButton extends StatefulWidget {
  const TvPiFocusButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = const Color(0xFF404040),
    this.autofocus = false,
    this.focusNode,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.fontSize = 16,
    this.labelOffset = Offset.zero,
    this.borderRadius,
  });

  final String label;
  final VoidCallback onPressed;
  final Color color;
  final bool autofocus;
  final FocusNode? focusNode;
  final EdgeInsets padding;
  final double fontSize;
  final Offset labelOffset;
  /// 指定時は固定角丸（お知らせ左メニューは 10px）。未指定は幅の 5%。
  final double? borderRadius;

  @override
  State<TvPiFocusButton> createState() => _TvPiFocusButtonState();
}

class _TvPiFocusButtonState extends State<TvPiFocusButton> {
  bool _focused = false;
  FocusNode? _externalNode;

  @override
  void initState() {
    super.initState();
    _listen(widget.focusNode);
  }

  @override
  void didUpdateWidget(TvPiFocusButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      _listen(widget.focusNode);
    }
    final has = widget.focusNode?.hasFocus;
    if (has != null && has != _focused) {
      _focused = has;
    }
  }

  @override
  void dispose() {
    _externalNode?.removeListener(_onExternalFocus);
    super.dispose();
  }

  void _listen(FocusNode? node) {
    _externalNode?.removeListener(_onExternalFocus);
    _externalNode = node;
    _externalNode?.addListener(_onExternalFocus);
    final has = node?.hasFocus;
    if (has != null) {
      _focused = has;
    }
  }

  void _onExternalFocus() {
    final has = _externalNode?.hasFocus ?? false;
    if (!mounted || has == _focused) return;
    setState(() => _focused = has);
  }

  static const _focusColor = Color(0xFF0099FF);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width * 0.15;
        final height = constraints.maxHeight.isFinite && constraints.maxHeight > 0
            ? constraints.maxHeight
            : null;
        final radius = widget.borderRadius ?? width * 0.05;
        final bg = _focused ? _focusColor : widget.color;
        final button = AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: width,
          height: height,
          alignment: Alignment.center,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0xFF999999)),
          ),
          child: Transform.translate(
            offset: widget.labelOffset,
            child: Text(
              widget.label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: widget.fontSize,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
          ),
        );

        if (!TvUtil.isTelevision) {
          return GestureDetector(onTap: widget.onPressed, child: button);
        }

        return Focus(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          onFocusChange: (hasFocus) {
            if (_focused != hasFocus) {
              setState(() => _focused = hasFocus);
            }
            if (hasFocus) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                Scrollable.ensureVisible(
                  context,
                  alignment: 0.45,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                );
              });
            }
          },
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.select ||
                    event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              widget.onPressed();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(onTap: widget.onPressed, child: button),
        );
      },
    );
  }
}
