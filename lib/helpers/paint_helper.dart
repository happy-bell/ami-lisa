import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

mixin PaintControllerDelegate {
  void onPaint(data);
}

class _PaintData {

  _PaintData({
    required this.path,
  }) : super();

  Path path; //  パス
}

class PaintHistory {
  // ペイントの履歴リスト
  List<MapEntry<_PaintData, Paint>> _paintList = <MapEntry<_PaintData, Paint>>[];
  // ペイントundoリスト
  List<MapEntry<_PaintData, Paint>> _undoneList = <MapEntry<_PaintData, Paint>>[];
  // 背景ペイント
  Paint _backgroundPaint = Paint();
  // ドラッグ中フラグ
  bool _inDrag = false;
  // カレントペイント
  late Paint currentPaint;
  late Paint erasePaint;

  bool _isClear = false;
  set isClear(value) => _isClear = value;

  /*
   * undo可能か
   */
  bool canUndo() => _paintList.length > 0;

  /*
   * redo可能か
   */
  bool canRedo() => _undoneList.length > 0;

  /*
   * undo
   */
  void undo() {

    if (!_inDrag && canUndo()) {
      _undoneList.add(_paintList.removeLast());
    }
  }

  /*
   * redo
   */
  void redo() {

    if (!_inDrag && canRedo()) {
      _paintList.add(_undoneList.removeLast());
    }
  }

  /*
   * クリア
   */
  void clear() {

    if (!_inDrag) {
      _paintList.clear();
      _undoneList.clear();
    }
  }

  /*
   * 背景色セッター
   */
  set backgroundColor(color) => _backgroundPaint.color = color;

  /*
   * 線ペイント開始
   */
  void addPaint(Offset startPoint) {

    if (!_inDrag) {
      _inDrag = true;
      Path path = Path();
      path.moveTo(startPoint.dx, startPoint.dy);
      _PaintData data = _PaintData(path: path);
      _paintList.add(MapEntry<_PaintData, Paint>(data, (_isClear ? erasePaint : currentPaint)));
    }
  }

  /*
   * 線ペイント更新
   */
  void updatePaint(Offset nextPoint) {

    if (_inDrag) {

      _PaintData data = _paintList.last.key;
      Path path = data.path;
      path.lineTo(nextPoint.dx, nextPoint.dy);
    }
  }

  /*
   * 線ペイント終了
   */
  void endPaint() {

    _inDrag = false;
  }

  /*
   * 描写
   */
  void draw(Canvas canvas, Size size) async {
    canvas.saveLayer(Rect.fromLTWH(
      0.0,
      0.0,
      size.width,
      size.height,
    ), Paint());
    canvas.drawRect(
      Rect.fromLTWH(
        0.0,
        0.0,
        size.width,
        size.height,
      ),
      _backgroundPaint,
    );

    /*
     * 線描写
     */
    for (MapEntry<_PaintData, Paint> data in _paintList) {
      if (data.key.path != null) {
        canvas.drawPath(data.key.path, data.value);
      }
    }
    canvas.restore();
  }
}

/*
 * ペイント
 */
class Painter extends StatefulWidget {

  // ペイントコントローラ
  final PaintController paintController;
  ui.Image image;
  ByteData? imageData;
  double width;
  double height;

  Painter({
    required this.paintController,
    required this.image,
    required this.width,
    required this.height,
  }) : super(key: ValueKey<PaintController>(paintController)) {

    assert(this.paintController != null);
  }

  @override
  _PainterState createState() => _PainterState();
}

/*
 * ペイント ステート
 */
class _PainterState extends State<Painter> {
  double lastX = 0;
  double lastY = 0;

  @override
  Widget build(BuildContext context) {

    return Container(

      // イベント監視
      child: GestureDetector(

        // カスタムペイント
        child: CustomPaint(
          willChange: true,

          // ペイント部分
          painter: _CustomPainter(
            widget.paintController._paintHistory,
            widget.paintController._paint2History,
            widget.image,
            repaint: widget.paintController,
          ),
        ),

        // イベントリスナー
        onPanStart: _onPaintStart,
        onPanUpdate: _onPaintUpdate,
        onPanEnd: _onPaintEnd,

      ),
      width: widget.width,
      height: widget.height,
    );
  }

  /*
   * 線ペイントの開始
   */
  void _onPaintStart(DragStartDetails start) {

    widget.paintController.delegate?.onPaint({'event': 'began', 'x': start.localPosition.dx.toString(), 'y': start.localPosition.dy.toString()});
    widget.paintController._paintHistory.addPaint(_getGlobalToLocalPosition(start.globalPosition));
    widget.paintController._notifyListeners();

    lastX = start.localPosition.dx;
    lastY = start.localPosition.dy;
  }

  /*
   * 線ペイント更新
   */
  void _onPaintUpdate(DragUpdateDetails update) {
    print(update.localPosition);
    print(widget.height);
    if (update.localPosition.dx < 0 || update.localPosition.dx > widget.width ||
        update.localPosition.dy < 0 || update.localPosition.dy > widget.height) {
      widget.paintController.delegate?.onPaint({'event': 'ended', 'x': lastX.toString(), 'y': lastY.toString()});
      widget.paintController._paintHistory.endPaint();
      widget.paintController._notifyListeners();
      return;
    }
    widget.paintController.delegate?.onPaint({'event': 'moved', 'x': update.localPosition.dx.toString(), 'y': update.localPosition.dy.toString()});
    widget.paintController._paintHistory.updatePaint(_getGlobalToLocalPosition(update.globalPosition));
    widget.paintController._notifyListeners();

    lastX = update.localPosition.dx;
    lastY = update.localPosition.dy;
  }

  /*
   * 線ペイントの終了
   */
  void _onPaintEnd(DragEndDetails end) {
    widget.paintController.delegate?.onPaint({'event': 'ended', 'x': lastX.toString(), 'y': lastY.toString()});
    widget.paintController._paintHistory.endPaint();
    widget.paintController._notifyListeners();
  }

  /*
   * ローカルのオフセットへ変換
   */
  Offset _getGlobalToLocalPosition(Offset global) {

    return (context.findRenderObject() as RenderBox).globalToLocal(global);
  }
}

/*
 * カスタムペイント
 */
class _CustomPainter extends CustomPainter {

  final PaintHistory _paintHistory;
  final PaintHistory _paint2History;
  ui.Image image;
  ByteData? imageData;

  _CustomPainter(
      this._paintHistory,
      this._paint2History,
      this.image,
      {
        required Listenable repaint
      }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    // ByteData data = image.toByteData();
    // canvas.drawImage(image, new Offset(0.0, 0.0), new Paint());

    final src = Rect.fromLTWH(0.0, 0.0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(0.0, 0.0, size.width, size.height);
    canvas.drawImageRect(image, src, dst, new Paint());

    _paintHistory.draw(canvas, size);

    _paint2History.draw(canvas, size);
  }

  @override
  bool shouldRepaint(_CustomPainter oldDelegate) => true;
}

/*
 * ペイントコントローラ
 */
class PaintController extends ChangeNotifier {
  // ペイント履歴
  PaintHistory _paintHistory = PaintHistory();
  PaintHistory _paint2History = PaintHistory();

  PaintControllerDelegate? delegate;

  // 線の色
  Color _drawColor = Color.fromARGB(255, 255, 0, 0);
  Color _draw2Color = Color.fromARGB(255, 255, 0, 0);
  // 線幅
  double _thickness = 5.0;
  // 背景色
  Color _backgroundColor = Color.fromARGB(0, 255, 255, 255);

  /*
   * コンストラクタ
   */
  PaintController() : super() {

    // ペイント設定
    // Paint paint = Paint();
    // paint.color = _drawColor;
    // paint.style = PaintingStyle.stroke;
    // paint.strokeWidth = _thickness;
    // _paintHistory.currentPaint = paint;
    // _paintHistory.backgroundColor = _backgroundColor;
  }

  /*
   * drawColor変更(1: host 2: guest)
   */
  void setDrawColor(int type) {
    if (type == 1) {
      _drawColor = Color.fromARGB(255, 0, 0, 255);
      _draw2Color = Color.fromARGB(255, 255, 0, 0);
    } else {
      _drawColor = Color.fromARGB(255, 255, 0, 0);
      _draw2Color = Color.fromARGB(255, 0, 0, 255);
    }
    Paint paint = Paint();
    paint.color = _drawColor;
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = _thickness;
    _paintHistory.currentPaint = paint;
    Paint erasepaint = Paint();
    erasepaint.style = PaintingStyle.stroke;
    erasepaint.strokeWidth = _thickness * 3;
    erasepaint.blendMode = BlendMode.clear;
    _paintHistory.erasePaint = erasepaint;
    _paintHistory.backgroundColor = _backgroundColor;

    Paint paint2 = Paint();
    paint2.color = _draw2Color;
    paint2.style = PaintingStyle.stroke;
    paint2.strokeWidth = _thickness;
    _paint2History.currentPaint = paint2;
    Paint erasepaint2 = Paint();
    erasepaint2.style = PaintingStyle.stroke;
    erasepaint2.strokeWidth = _thickness * 3;
    erasepaint2.blendMode = BlendMode.clear;
    _paint2History.erasePaint = erasepaint2;
    _paint2History.backgroundColor = _backgroundColor;
  }

  void setIsClear(bool isClear) {
    _paintHistory.isClear = isClear;
  }

  void setIsClear2(bool isClear) {
    _paint2History.isClear = isClear;
  }

  void receiveDraw(String event, double x, double y) {
    print('receive draw $event');
    Offset offset = new Offset(x, y);
    if (event == 'began') {
      _paint2History.addPaint(offset);
    } else if (event == 'moved') {
      _paint2History.updatePaint(offset);
    } else if (event == 'end' || event == 'ended') {
      _paint2History.endPaint();
    } else if (event == 'undo') {
      _paint2History.undo();
    }
    _notifyListeners();
  }

  /*
   * undo実行
   */
  void undo() {

    _paintHistory.undo();
    notifyListeners();
  }

  /*
   * redo実行
   */
  void redo() {

    _paintHistory.redo();
    notifyListeners();
  }

  /*
   * undo可能か
   */
  bool get canUndo => _paintHistory.canUndo();

  /*
   * redo可能か
   */
  bool get canRedo => _paintHistory.canRedo();

  /*
   * リスナー実行
   */
  void _notifyListeners() {

    notifyListeners();
  }

  /*
   * クリア
   */
  void clear() {
    _paintHistory.clear();
    notifyListeners();
  }

  void clear2() {
    _paint2History.clear();
    notifyListeners();
  }

  Future<ui.Image> image(ui.Image image, Size size) {
    ui.PictureRecorder recorder = ui.PictureRecorder();
    Canvas canvas = Canvas(recorder);
    final src = Rect.fromLTWH(0.0, 0.0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(0.0, 0.0, size.width, size.height);
    canvas.drawImageRect(image, src, dst, new Paint());

    _paintHistory.draw(canvas, size);

    _paint2History.draw(canvas, size);

    return recorder.endRecording()
        .toImage(size.width.floor(), size.height.floor());
  }
}
