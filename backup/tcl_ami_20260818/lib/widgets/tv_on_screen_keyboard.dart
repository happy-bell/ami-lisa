import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Google TV リモコン（D-pad）で操作できるオンスクリーンキーボード。
class TvOnScreenKeyboard extends StatefulWidget {
  const TvOnScreenKeyboard({
    super.key,
    required this.controller,
    this.onNext,
    this.onDone,
    this.firstKeyFocusNode,
  });

  final TextEditingController controller;
  final VoidCallback? onNext;
  final VoidCallback? onDone;

  /// 親からフォーカスを渡す用（起動時・欄切替時に requestFocus する）
  final FocusNode? firstKeyFocusNode;

  @override
  State<TvOnScreenKeyboard> createState() => _TvOnScreenKeyboardState();
}

class _TvOnScreenKeyboardState extends State<TvOnScreenKeyboard> {
  bool _upper = false;
  bool _symbolMode = false;

  static const _rowsLower = <List<String>>[
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p'],
    ['a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l'],
    ['z', 'x', 'c', 'v', 'b', 'n', 'm'],
  ];

  /// スタンダードな記号レイアウト
  static const _rowsSymbols = <List<String>>[
    ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'],
    ['!', '@', '#', '\$', '%', '^', '&', '*', '(', ')'],
    ['-', '_', '=', '+', '[', ']', '{', '}', ';', ':'],
    ['\'', '"', '\\', '|', '/', '?', ',', '.', '<', '>'],
    ['~', '`', '¥', '€', '£', '•', '±', '×', '÷', '°'],
  ];

  List<List<String>> get _rows {
    if (_symbolMode) return _rowsSymbols;
    return _rowsLower
        .map((row) => row
            .map((k) =>
                _upper && RegExp(r'^[a-z]$').hasMatch(k) ? k.toUpperCase() : k)
            .toList())
        .toList();
  }

  void _insert(String text) {
    final value = widget.controller.value;
    final textValue = value.text;
    final start =
        value.selection.isValid ? value.selection.start : textValue.length;
    final end =
        value.selection.isValid ? value.selection.end : textValue.length;
    final safeStart = start.clamp(0, textValue.length);
    final safeEnd = end.clamp(0, textValue.length);
    final newText = textValue.replaceRange(safeStart, safeEnd, text);
    final cursor = safeStart + text.length;
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }

  void _backspace() {
    final value = widget.controller.value;
    if (value.selection.isValid && !value.selection.isCollapsed) {
      _insert('');
      return;
    }
    final offset = value.selection.isValid
        ? value.selection.baseOffset
        : value.text.length;
    if (offset <= 0) return;
    final newText =
        value.text.substring(0, offset - 1) + value.text.substring(offset);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: offset - 1),
    );
  }

  Widget _key({
    required String label,
    required VoidCallback onPressed,
    double flex = 1,
    FocusNode? focusNode,
    bool autofocus = false,
    Color? color,
  }) {
    return Expanded(
      flex: (flex * 10).round(),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: _TvKeyButton(
          label: label,
          focusNode: focusNode,
          autofocus: autofocus,
          color: color,
          onPressed: onPressed,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;

    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Material(
        color: const Color(0xFF1E1E1E),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var r = 0; r < rows.length; r++)
                  Row(
                    children: [
                      for (var c = 0; c < rows[r].length; c++)
                        _key(
                          label: rows[r][c],
                          focusNode: (r == 0 && c == 0)
                              ? widget.firstKeyFocusNode
                              : null,
                          autofocus: false,
                          onPressed: () => _insert(rows[r][c]),
                        ),
                    ],
                  ),
                Row(
                  children: [
                    if (!_symbolMode)
                      _key(
                        label: _upper ? 'abc' : 'ABC',
                        flex: 1.3,
                        color: const Color(0xFF333333),
                        onPressed: () => setState(() => _upper = !_upper),
                      ),
                    _key(
                      label: _symbolMode ? 'ABC' : '記号',
                      flex: 1.3,
                      color: const Color(0xFF0B5CAB),
                      onPressed: () => setState(() {
                        _symbolMode = !_symbolMode;
                        if (_symbolMode) _upper = false;
                      }),
                    ),
                    _key(
                      label: '@',
                      flex: 1.0,
                      onPressed: () => _insert('@'),
                    ),
                    _key(
                      label: '.',
                      flex: 1.0,
                      onPressed: () => _insert('.'),
                    ),
                    _key(
                      label: '_',
                      flex: 1.0,
                      onPressed: () => _insert('_'),
                    ),
                    _key(
                      label: '-',
                      flex: 1.0,
                      onPressed: () => _insert('-'),
                    ),
                    _key(
                      label: '⌫',
                      flex: 1.6,
                      color: const Color(0xFF5A3A00),
                      onPressed: _backspace,
                    ),
                    if (widget.onNext != null || widget.onDone != null)
                      _key(
                        label: widget.onDone != null ? 'ログイン' : '次へ',
                        flex: 1.6,
                        color: const Color(0xFF0B5CAB),
                        onPressed: () {
                          if (widget.onDone != null) {
                            widget.onDone!();
                          } else {
                            widget.onNext?.call();
                          }
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TvKeyButton extends StatefulWidget {
  const _TvKeyButton({
    required this.label,
    required this.onPressed,
    this.focusNode,
    this.autofocus = false,
    this.color,
  });

  final String label;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool autofocus;
  final Color? color;

  @override
  State<_TvKeyButton> createState() => _TvKeyButtonState();
}

class _TvKeyButtonState extends State<_TvKeyButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      onFocusChange: (v) {
        if (_focused != v) setState(() => _focused = v);
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.select ||
            event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          widget.onPressed();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _focused
                ? const Color(0xFF4FC3F7)
                : (widget.color ?? const Color(0xFF2C2C2C)),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? Colors.white : Colors.white24,
              width: _focused ? 3 : 1,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: _focused ? Colors.black : Colors.white,
              fontSize: widget.label.length > 2 ? 13 : 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
