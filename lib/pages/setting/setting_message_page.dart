import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/tv_message_schedule.dart';
import 'package:amiapp/widgets/tv_focusable.dart';

class SettingMessagePage extends StatefulWidget {
  const SettingMessagePage({
    super.key,
    this.title = 'メッセージ',
    this.settingKey = TvMessageSchedule.messageKey,
    this.colorTitle = '明るさ',
  });

  final String title;
  final String settingKey;
  final String colorTitle;

  @override
  State<SettingMessagePage> createState() => _SettingMessagePageState();
}

class _SettingMessagePageState extends State<SettingMessagePage> {
  late List<TvMessageSlot> _slots;
  String _clockFace = '1';

  bool get _isClock => widget.settingKey == TvMessageSchedule.clockKey;

  bool get _showClockFace =>
      _isClock && TvUtil.isTelevision && AppManager.isPiTvLayout;

  @override
  void initState() {
    super.initState();
    _slots = TvMessageSchedule.load(widget.settingKey);
    if (_showClockFace) {
      _clockFace = TvMessageSchedule.clockFace();
    }
  }

  Future<void> _edit(int index) async {
    final result = await Navigator.of(context).push<TvMessageSlot>(
      MaterialPageRoute(
        builder: (_) => _SettingMessageSlotPage(
          index: index,
          slot: _slots[index],
          colorTitle: widget.colorTitle,
          paletteKey: widget.settingKey,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _slots[index] = result;
    });
    await TvMessageSchedule.save(_slots, key: widget.settingKey);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: WidgetUtil.appBar(
        widget.title,
        backgroundColor: WidgetUtil.iosNavbarBG,
        foregroundColor: Colors.black,
      ),
      backgroundColor: const Color.fromARGB(255, 240, 240, 240),
      body: ListView(
        children: [
          for (var i = 0; i < _slots.length; i++)
            nextRow(
              '時間帯${i + 1}',
              _slots[i].enabled
                  ? '${_slots[i].rangeLabel}  ${_slots[i].colorLabel}'
                  : '表示しない',
              () => _edit(i),
              autofocus: TvUtil.isTelevision && i == 0,
              color: _slots[i].enabled ? _slots[i].color : null,
            ),
          if (_showClockFace) ...[
            _faceRow('デジタル', '0'),
            _faceRow('デジタル日付', '1'),
          ],
        ],
      ),
    );
  }

  Widget nextRow(
    String title,
    String subtitle,
    VoidCallback onTap, {
    bool autofocus = false,
    Color? color,
  }) {
    final height = TvUtil.isTelevision ? 64.0 : WidgetUtil.listHeight;
    final style = TextStyle(fontSize: TvUtil.isTelevision ? 22 : 14);
    return TvSettingFocus(
      autofocus: autofocus,
      onActivate: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            if (color != null) ...[
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(child: Text(title, style: style)),
            Text(subtitle, style: style),
            const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _faceRow(String title, String value) {
    final height = TvUtil.isTelevision ? 64.0 : WidgetUtil.listHeight;
    final style = TextStyle(fontSize: TvUtil.isTelevision ? 22 : 14);
    return TvSettingFocus(
      onActivate: () async {
        setState(() {
          _clockFace = value;
        });
        await TvMessageSchedule.saveClockFace(value);
      },
      child: Container(
        height: height,
        padding: const EdgeInsets.all(10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: style),
            if (_clockFace == value) WidgetUtil.listCheckIcon,
          ],
        ),
      ),
    );
  }
}

class _SettingMessageSlotPage extends StatefulWidget {
  const _SettingMessageSlotPage({
    required this.index,
    required this.slot,
    this.colorTitle = '明るさ',
    this.paletteKey = TvMessageSchedule.messageKey,
  });

  final int index;
  final TvMessageSlot slot;
  final String colorTitle;
  final String paletteKey;

  @override
  State<_SettingMessageSlotPage> createState() => _SettingMessageSlotPageState();
}

class _SettingMessageSlotPageState extends State<_SettingMessageSlotPage> {
  late TvMessageSlot _slot;

  @override
  void initState() {
    super.initState();
    _slot = widget.slot;
  }

  void _nudgeStart(int delta) {
    setState(() {
      _slot = _slot.copyWith(
        startMin: (_slot.startMin + delta).clamp(0, 1425),
      );
    });
  }

  void _nudgeEnd(int delta) {
    setState(() {
      _slot = _slot.copyWith(
        endMin: (_slot.endMin + delta).clamp(0, 1440),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        Navigator.of(context).pop(_slot);
        return false;
      },
      child: Scaffold(
        appBar: WidgetUtil.appBar(
          '時間帯${widget.index + 1}',
          backgroundColor: WidgetUtil.iosNavbarBG,
          foregroundColor: Colors.black,
        ),
        backgroundColor: const Color.fromARGB(255, 240, 240, 240),
        body: ListView(
          children: [
            TvSettingFocus(
              autofocus: TvUtil.isTelevision,
              onActivate: () {
                setState(() {
                  _slot = _slot.copyWith(enabled: !_slot.enabled);
                });
              },
              child: _row(
                '表示',
                _slot.enabled ? 'する' : 'しない',
              ),
            ),
            _stepRow(
              '開始',
              TvMessageSchedule.formatMin(_slot.startMin),
              onLeft: () => _nudgeStart(-15),
              onRight: () => _nudgeStart(15),
            ),
            _stepRow(
              '終了',
              TvMessageSchedule.formatMin(_slot.endMin),
              onLeft: () => _nudgeEnd(-15),
              onRight: () => _nudgeEnd(15),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                widget.colorTitle,
                style: TextStyle(fontSize: TvUtil.isTelevision ? 22 : 14),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (var i = 0; i < TvMessageSchedule.brightnessCount; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: TvFocusable(
                          borderRadius: 8,
                          // フォーカス枠は既定の水色（#4FC3F7）を使う。
                          onPressed: () {
                            setState(() {
                              _slot = _slot.copyWith(colorIndex: i);
                            });
                          },
                          childBuilder: (context, focused) => Container(
                            height: TvUtil.isTelevision ? 72 : 56,
                            decoration: BoxDecoration(
                              color: const Color(0xFF333333),
                              borderRadius: BorderRadius.circular(8),
                              // リモコンでフォーカス中は水色の太い枠で示す。
                              // 選択中(確定)は従来どおり #0099FF の枠。
                              border: Border.all(
                                color: focused
                                    ? const Color(0xFF4FC3F7)
                                    : (_slot.colorIndex == i
                                        ? const Color(0xFF0099FF)
                                        : Colors.transparent),
                                width: focused ? 6 : 3,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: TvMessageSchedule.colorAt(
                                      i,
                                      key: widget.paletteKey,
                                    ),
                                    border: Border.all(color: Colors.white54),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                // 文字を大きくしたので、幅が足りないときは
                                // 折り返さず自動縮小して1行に収める。
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    TvMessageSchedule.labelAt(i),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    style: TextStyle(
                                      color: Colors.white,
                                      // 明るい〜暗いの5段階ラベルは従来比135%。
                                      fontSize: TvUtil.isTelevision ? 18 : 15,
                                    ),
                                  ),
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
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Text(
                '開始・終了は左右で15分ずつ変えます。戻ると保存します。',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String title, String value) {
    final height = TvUtil.isTelevision ? 64.0 : WidgetUtil.listHeight;
    final style = TextStyle(fontSize: TvUtil.isTelevision ? 22 : 14);
    return Container(
      height: height,
      padding: const EdgeInsets.all(10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: style),
          Text(value, style: style),
        ],
      ),
    );
  }

  Widget _stepRow(
    String title,
    String value, {
    required VoidCallback onLeft,
    required VoidCallback onRight,
  }) {
    final height = TvUtil.isTelevision ? 64.0 : WidgetUtil.listHeight;
    final style = TextStyle(fontSize: TvUtil.isTelevision ? 22 : 14);
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
          onLeft();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
          onRight();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final focused = Focus.of(context).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            height: height,
            decoration: BoxDecoration(
              color: focused ? const Color(0xFFD6F0FF) : Colors.white,
              border: Border(
                bottom: const BorderSide(color: Color.fromARGB(255, 220, 220, 220)),
                left: BorderSide(
                  color: focused ? const Color(0xFF4FC3F7) : Colors.transparent,
                  width: 4,
                ),
              ),
            ),
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(child: Text(title, style: style)),
                ExcludeFocus(
                  child: IconButton(
                    onPressed: onLeft,
                    icon: const Icon(Icons.chevron_left),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: Text(value, textAlign: TextAlign.center, style: style),
                ),
                ExcludeFocus(
                  child: IconButton(
                    onPressed: onRight,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
