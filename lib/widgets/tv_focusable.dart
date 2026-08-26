import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:amiapp/helpers/tv_util.dart';

/// リモコン（D-pad）でフォーカス可能なラッパー。
/// スマホでは見た目を変えず、子の onTap 相当を [onPressed] に任せる。
class TvFocusable extends StatefulWidget {
  const TvFocusable({
    super.key,
    this.child,
    this.onPressed,
    this.autofocus = false,
    this.borderRadius = 8,
    this.focusColor = const Color(0xFF4FC3F7),
    this.enabled = true,
    this.childBuilder,
  }) : assert(child != null || childBuilder != null,
            'child か childBuilder のどちらかを指定すること');

  final Widget? child;
  final VoidCallback? onPressed;
  final bool autofocus;
  final double borderRadius;
  final Color focusColor;
  final bool enabled;

  /// フォーカス状態に応じて中身を変えたいときに使う（背景色を変える等）。
  /// 指定した場合は [child] ではなくこちらを描画する。
  final Widget Function(BuildContext context, bool focused)? childBuilder;

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    if (!TvUtil.isTelevision) {
      return widget.childBuilder?.call(context, false) ??
          widget.child ??
          const SizedBox.shrink();
    }

    return Focus(
      autofocus: widget.autofocus,
      canRequestFocus: widget.enabled,
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
        if (!widget.enabled || widget.onPressed == null) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onPressed!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            color: _focused ? widget.focusColor : Colors.transparent,
            width: _focused ? 3 : 0,
          ),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: widget.focusColor.withValues(alpha: 0.45),
                    blurRadius: 12,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: widget.childBuilder?.call(context, _focused) ?? widget.child,
      ),
    );
  }
}

/// 設定リスト行向け。TVでは左青バー＋背景、決定で [onActivate]。
class TvSettingFocus extends StatelessWidget {
  const TvSettingFocus({
    super.key,
    required this.child,
    required this.onActivate,
    this.autofocus = false,
  });

  final Widget child;
  final VoidCallback onActivate;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    if (!TvUtil.isTelevision) {
      return InkWell(onTap: onActivate, child: child);
    }
    return Focus(
      autofocus: autofocus,
      onFocusChange: (hasFocus) {
        if (!hasFocus) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          Scrollable.ensureVisible(
            context,
            alignment: 0.45,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
          );
        });
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          onActivate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            decoration: BoxDecoration(
              color: focused ? const Color(0xFFD6F0FF) : Colors.white,
              border: Border(
                bottom: const BorderSide(
                    color: Color.fromARGB(255, 220, 220, 220)),
                left: BorderSide(
                  color: focused ? const Color(0xFF4FC3F7) : Colors.transparent,
                  width: 4,
                ),
              ),
            ),
            child: InkWell(onTap: onActivate, child: child),
          );
        },
      ),
    );
  }
}

/// ダイアログの「はい／いいえ」など。TVでは決定で押せる。
class TvDialogAction extends StatelessWidget {
  const TvDialogAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      onPressed: onPressed,
      child: ExcludeFocus(
        child: TextButton(
          onPressed: onPressed,
          child: Text(label, style: const TextStyle(fontSize: 20)),
        ),
      ),
    );
  }
}
