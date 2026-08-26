import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/helpers/widget_util.dart';
import 'package:amiapp/services/hazard_map_service.dart';
import 'package:amiapp/services/jma_alert_service.dart';
import 'package:amiapp/widgets/tv_pi_focus_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class _RasterLayer {
  const _RasterLayer(this.label, this.tile, this.legend);
  final String label;
  final String tile;

  /// 地図の色が何を意味するかの凡例。色は実際のタイルから採取した値。
  final List<_LegendItem> legend;
}

class _LegendItem {
  const _LegendItem(this.color, this.label);
  final Color color;
  final String label;
}

/// 洪水・津波・高潮で共通の浸水深の凡例（国土交通省の標準配色）。
const _depthLegend = [
  _LegendItem(Color(0xFFF7F5A9), '0.5m未満'),
  _LegendItem(Color(0xFFFFD8C0), '0.5〜3m'),
  _LegendItem(Color(0xFFFFB7B7), '3〜5m'),
  _LegendItem(Color(0xFFFF9191), '5〜10m'),
  _LegendItem(Color(0xFFF285C9), '10〜20m'),
  _LegendItem(Color(0xFFDC7ADC), '20m以上'),
];

/// お知らせページの「HM」ボタンから開くハザードマップ・防災情報ページ（PoC）。
/// 不動産情報ライブラリAPI（国土交通省）でリスク判定、国土地理院タイルで地図表示。
/// 対象地点は「設定 → 天気予報」で選んだ地域に連動する。
class HazardMapPage extends StatefulWidget {
  const HazardMapPage({super.key});

  @override
  State<HazardMapPage> createState() => _HazardMapPageState();
}

class _HazardMapPageState extends State<HazardMapPage> {
  bool _loading = true;
  HazardMapData? _data;
  int _selectedLayer = 0;
  /// 気象庁の防災情報（発表中の警報・注意報／直近の地震）。
  List<JmaWarning> _warnings = const [];
  List<JmaQuake> _quakes = const [];

  // TV(Android TV)でリモコンD-padから右側コンテンツをスクロールするための制御。
  final ScrollController _scrollController = ScrollController();
  final FocusNode _contentFocus = FocusNode(debugLabel: 'hazardContent');
  bool _contentFocused = false;

  /// 選択中のレイヤーを示す色。フォーカス色(#0099FF)と混同しない赤。
  /// お知らせページの「停止」ボタンと同じ赤に合わせている。
  static const _selectedColor = Color(0xFFCC3333);

  /// 地図のズーム。判定用タイル(z15)より1段引いて約6km四方を映す。
  static const _mapZoom = 14;
  /// 並べるタイル枚数（_mapTiles × _mapTiles）。
  static const _mapTiles = 3;
  /// 地図の表示サイズ(px)の上限。タイル256px×3枚＝768。
  /// ただし表示領域(TV005で約733px)を超えると右端のタイルが切れて
  /// 中心（対象地点）がずれるため、実際は表示幅に収まるよう縮める。
  static const _mapMaxSize = 768.0;

  static const _rasterLayers = [
    _RasterLayer('洪水', '01_flood_l2_shinsuishin_data', _depthLegend),
    _RasterLayer('津波', '04_tsunami_newlegend_data', _depthLegend),
    _RasterLayer('高潮', '03_hightide_l2_shinsuishin_data', _depthLegend),
    _RasterLayer('土砂災害', '05_dosekiryukeikaikuiki', [
      _LegendItem(Color(0xFFE6C832), '土石流警戒区域'),
    ]),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _contentFocus.dispose();
    super.dispose();
  }

  /// D-pad上下でスクロール。direction=1で下、-1で上。webview_pageと同じ操作感。
  void _scrollBy(int direction) {
    if (!_scrollController.hasClients) return;
    final step = 260.0;
    final target = (_scrollController.offset + direction * step)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
    );
  }

  Future<void> _load() async {
    final data = await HazardMapService.instance.fetchAll();
    // 気象庁の防災情報。取得できなくてもハザードマップ表示は続ける。
    final warnings = await JmaAlertService.instance.fetchWarnings();
    final quakes = await JmaAlertService.instance.fetchQuakes(limit: 3);
    if (!mounted) return;
    setState(() {
      _data = data;
      _warnings = warnings;
      _quakes = quakes;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F0),
      appBar: WidgetUtil.appBar(
        'ハザードマップ・防災情報',
        backgroundColor: WidgetUtil.iosNavbarBG,
        foregroundColor: Colors.black,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                SizedBox(
                  width: 180,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _sideBtn(
                        '戻る',
                        const Color(0xFF5CB85C),
                        () => Navigator.of(context).pop(),
                        autofocus: TvUtil.isTelevision,
                      ),
                      // いま地図に出しているレイヤーを赤で示す。
                      // 以前は #0099FF だったが TvPiFocusButton のフォーカス色と
                      // 同じで「選択中」と「カーソルが当たっている」の区別が
                      // つかなかったため、フォーカス(青)と別系統の赤にしている。
                      for (var i = 0; i < _rasterLayers.length; i++)
                        _sideBtn(
                          _rasterLayers[i].label,
                          _selectedLayer == i
                              ? _selectedColor
                              : const Color(0xFF404040),
                          () => setState(() => _selectedLayer = i),
                        ),
                    ],
                  ),
                ),
                Expanded(child: _contentArea()),
              ],
            ),
    );
  }

  /// 右側コンテンツ。TVではリモコンD-padでスクロール・フォーカスできるようにする。
  /// スマホ／タッチ環境では従来どおりそのまま表示（指スクロール）。
  Widget _contentArea() {
    final content = _content();
    if (!TvUtil.isTelevision) return content;
    return Focus(
      focusNode: _contentFocus,
      onFocusChange: (has) {
        if (mounted && has != _contentFocused) {
          setState(() => _contentFocused = has);
        }
      },
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.pageDown) {
          _scrollBy(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp ||
            key == LogicalKeyboardKey.pageUp) {
          _scrollBy(-1);
          return KeyEventResult.handled;
        }
        // 左キーで左メニュー（洪水／津波…）へフォーカスを戻す。
        if (key == LogicalKeyboardKey.arrowLeft) {
          node.focusInDirection(TraversalDirection.left);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          border: Border.all(
            color:
                _contentFocused ? const Color(0xFF0099FF) : Colors.transparent,
            width: 3,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: content,
      ),
    );
  }

  Widget _sideBtn(String label, Color color, VoidCallback onPressed,
      {bool autofocus = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 56,
        child: TvPiFocusButton(
          label: label,
          onPressed: onPressed,
          color: color,
          autofocus: autofocus,
          fontSize: 20,
          borderRadius: 10,
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
      ),
    );
  }

  /// ハザードマップ表示。
  ///
  /// 以前はタイル1枚(256px)をカラム幅いっぱい(約1000px)まで引き伸ばしていたため、
  /// 極端に粗く、しかも下地が無いので「塗りつぶし色だけ」で何の地図か分からなかった。
  /// ここでは
  ///   ・ズームを1段引いて(z14)、3×3=9枚を並べて広い範囲を出す
  ///   ・地理院の淡色地図を下地に敷き、その上にハザード情報を半透明で重ねる
  ///   ・タイルは等倍以下（256px → 約173px）で描き、引き伸ばさない
  ///   ・中心（対象地点）にピンを立てる
  /// とすることで、道路・地名が見える普通の地図として読めるようにしている。
  Widget _hazardMap(_RasterLayer layer) {
    final center =
        HazardMapService.latLonToTile(hazardLatitude, hazardLongitude, _mapZoom);
    // 表示領域の幅に収める。はみ出すと右端のタイルが切れて中心がずれる。
    return LayoutBuilder(builder: (context, constraints) {
      final size = constraints.maxWidth.isFinite &&
              constraints.maxWidth < _mapMaxSize
          ? constraints.maxWidth
          : _mapMaxSize;
      final tileSize = size / _mapTiles;
      return Align(
        alignment: Alignment.centerLeft,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: size,
            height: size,
            color: const Color(0xFFEFEFEF),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 下地：地理院タイル（淡色地図）。道路・地名が見える。
                _tileGrid(
                  center,
                  tileSize,
                  (x, y) =>
                      'https://cyberjapandata.gsi.go.jp/xyz/pale/$_mapZoom/$x/$y.png',
                ),
                // 上：ハザード情報。下地が透けるように半透明で重ねる。
                Opacity(
                  opacity: 0.62,
                  child: _tileGrid(
                    center,
                    tileSize,
                    (x, y) =>
                        'https://disaportaldata.gsi.go.jp/raster/${layer.tile}/$_mapZoom/$x/$y.png',
                  ),
                ),
                // 対象地点。
                const Icon(Icons.place, size: 44, color: Color(0xFFD32F2F)),
              ],
            ),
          ),
        ),
      );
    });
  }

  /// 中心タイルを軸に [_mapTiles]×[_mapTiles] 枚を並べる。
  /// 取得できないタイル（未整備エリア等）は透明のまま空ける。
  Widget _tileGrid(
    TileXY center,
    double tileSize,
    String Function(int x, int y) url,
  ) {
    const half = _mapTiles ~/ 2;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var dy = -half; dy <= half; dy++)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var dx = -half; dx <= half; dx++)
                Image.network(
                  url(center.x + dx, center.y + dy),
                  width: tileSize,
                  height: tileSize,
                  fit: BoxFit.fill,
                  gaplessPlayback: true,
                  errorBuilder: (_, __, ___) =>
                      SizedBox(width: tileSize, height: tileSize),
                ),
            ],
          ),
      ],
    );
  }

  /// 地図の色の意味を示す凡例。色だけでは何の情報か分からないため必ず出す。
  Widget _legend(_RasterLayer layer) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('凡例',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        for (final item in layer.legend)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 26,
                height: 18,
                decoration: BoxDecoration(
                  color: item.color,
                  border: Border.all(color: Colors.black26),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 5),
              Text(item.label, style: const TextStyle(fontSize: 16)),
            ],
          ),
      ],
    );
  }

  Widget _content() {
    final data = _data;
    if (data == null) {
      return const Center(
        child: Text('取得に失敗しました', style: TextStyle(fontSize: 24)),
      );
    }
    final layer = _rasterLayers[_selectedLayer];

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          '対象地点: $hazardAreaLabel',
          style: const TextStyle(fontSize: 24, color: Colors.black54),
        ),
        const SizedBox(height: 16),
        // 気象庁の「いま出ている警報・注意報」を最上部に置く。
        ..._alertSection(),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final r in data.layers) _riskCard(r),
          ],
        ),
        const SizedBox(height: 24),
        Text('地図: ${layer.label}',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _hazardMap(layer),
        const SizedBox(height: 8),
        _legend(layer),
        const SizedBox(height: 6),
        Text(
          layer.label == '土砂災害'
              ? '赤いピンが対象地点です。色が付いた場所が警戒区域です。'
              : '赤いピンが対象地点です。色が濃いほど深く浸水すると想定されています。',
          style: const TextStyle(fontSize: 16),
        ),
        const Text(
          '出典: ハザードマップポータルサイト・地理院タイル（国土地理院）',
          style: TextStyle(fontSize: 13, color: Colors.black54),
        ),
        const SizedBox(height: 24),
        const Text('最寄りの指定緊急避難場所',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (data.shelter == null)
          const Text('このタイル範囲内に登録データがありません', style: TextStyle(fontSize: 18))
        else
          Text(
            '${data.shelter!.name}\n${data.shelter!.address}',
            style: const TextStyle(fontSize: 20),
          ),
        const SizedBox(height: 24),
        // 直近の地震情報（気象庁）。
        ..._quakeSection(),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3CD),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '本情報は気象庁・国土交通省・国土地理院の公開データに基づく参考情報です。\n'
            '避難の判断は必ず自治体の公式ハザードマップ・避難情報でご確認ください。',
            style: TextStyle(fontSize: 16),
          ),
        ),
      ],
    );
  }

  /// 気象庁の発表中の警報・注意報。見出しは常に出し、発表が無いときも
  /// 「発表なし」と明示する（情報が更新されていることが分かるように）。
  List<Widget> _alertSection() {
    return [
      Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          const Text('気象庁 警報・注意報',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(
            '（$_alertAreaLabel  ${_formatNow()}時点）',
            style: const TextStyle(fontSize: 18, color: Colors.black54),
          ),
        ],
      ),
      const SizedBox(height: 8),
      if (_warnings.isEmpty)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            border: Border.all(color: const Color(0xFF27C6A4), width: 2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            '発表中の警報・注意報はありません',
            style: TextStyle(fontSize: 20),
          ),
        )
      else
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final w in _warnings) _warningCard(w),
          ],
        ),
      const SizedBox(height: 20),
    ];
  }

  String get _alertAreaLabel => JmaAlertService.instance.lastAreaLabel;

  String _formatNow() {
    final n = DateTime.now();
    final h = n.hour.toString().padLeft(2, '0');
    final m = n.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Widget _warningCard(JmaWarning w) {
    // 特別警報=赤、警報=橙、注意報=黄。
    final color = w.isEmergency
        ? const Color(0xFFD32F2F)
        : (w.isWarning ? const Color(0xFFFF6F00) : const Color(0xFFFBC02D));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        w.name,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  /// 直近の地震情報（気象庁）。
  List<Widget> _quakeSection() {
    if (_quakes.isEmpty) return const [];
    return [
      const Text('最近の地震',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      for (final q in _quakes)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            '${q.datetime}  ${q.place}'
            '${q.magnitude.isEmpty ? '' : '  M${q.magnitude}'}'
            '${q.maxIntensity.isEmpty ? '' : '  最大震度${q.maxIntensity}'}',
            style: const TextStyle(fontSize: 18),
          ),
        ),
      const SizedBox(height: 16),
    ];
  }

  Widget _riskCard(HazardLayerResult r) {
    final color = r.hasRisk ? const Color(0xFFFFB547) : const Color(0xFF27C6A4);
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(r.label,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            r.hasRisk ? '該当あり' : '該当なし',
            style: TextStyle(
                fontSize: 18, color: color, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(r.detail, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }
}
