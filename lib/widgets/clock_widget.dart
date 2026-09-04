import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:amiapp/helpers/tv_util.dart';
import 'package:amiapp/services/appmanager.dart';
import 'package:amiapp/services/tv_message_schedule.dart';

class ClockWidget extends StatefulWidget {
  const ClockWidget({super.key, this.color, this.watching = false});

  final Color? color;
  final bool watching;

  @override
  _ClockWidgetState createState() => _ClockWidgetState();
}

class _ClockWidgetState extends State<ClockWidget> {
  Timer? _timer;
  var _nowTime = DateTime.now();
  var _text = '';
  var _yearText = '';
  var _dateText = '';

  @override
  void initState() {
    super.initState();
    print('clock initstate');
    _initTimer();
  }

  @override
  void dispose() {
    print('clock dispose');
    if (_timer != null) {
      _timer!.cancel();
    }
    super.dispose();
  }

  void _initTimer() {
    _text = AppManager.dateFormat(_nowTime, "HH:mm");
    _yearText = AppManager.dateFormat(_nowTime, "yyyy年");
    _dateText = AppManager.dateFormat(_nowTime, "MMMd日(EEE)");
    _timer = Timer.periodic(Duration(milliseconds: 1000), (Timer timer) {
      // print('clock timer');
      _nowTime = DateTime.now();
      var text = AppManager.dateFormat(_nowTime, "HH:mm");
      if (_text != text) {
        print(_text);
        setState(() {
          _text = text;
          _dateText = AppManager.dateFormat(_nowTime, "MMMd日(EEE)");
          _yearText = AppManager.dateFormat(_nowTime, "yyyy年");
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    var timeHeight = 180.0;
    var dateHeight = 100.0;
    var dateLeft = 100.0;
    var dateTimeMargin = 40.0;
    var centerY = MediaQuery.of(context).size.height / 2;
    var shortestSide = MediaQuery.of(context).size.shortestSide;
    var fontSize1 = 80.0;
    var fontSize2 = 200.0;
    // print(fontSize);
    if (shortestSide < 600) {
      timeHeight = 100;
      dateHeight = 60.0;
      dateLeft = 60.0;
      dateTimeMargin = 10;
      fontSize1 = 40.0;
      fontSize2 = 100.0;
    }
    if (AppManager.isPiTvLayout || TvUtil.isTelevision) {
      return _piClock(
        timeHeight: timeHeight * 1.3,
        dateHeight: dateHeight,
        dateTimeMargin: dateTimeMargin,
        centerY: centerY,
        fontSize1: fontSize1,
        fontSize2: fontSize2 * 1.3,
        screenWidth: MediaQuery.of(context).size.width,
        color: widget.color ?? TvMessageSchedule.currentClockColor(),
        watching: widget.watching,
      );
    }
    var text = _text;
    if (AppManager.appsettings['SLEEP_CLOCK'] == '1') {
      text = "$_dateText\n$_text";
    }
    return Stack(
      children: <Widget>[
        if (AppManager.appsettings['SLEEP_CLOCK'] == '1')
          ... [
            Positioned(
              top: centerY - (timeHeight / 2) - (dateHeight * 2) - dateTimeMargin,
              left: dateLeft,
              width: MediaQuery.of(context).size.width,
              height: dateHeight,
              child: Text(_yearText,
                  style: TextStyle(
                    color: const Color.fromARGB(255, 129, 146, 92),
                    fontSize: fontSize1,
                    fontWeight: FontWeight.bold,
                  )
              ),
            ),
            Positioned(
              top: centerY - (timeHeight / 2) - dateHeight - dateTimeMargin,
              left: dateLeft,
              width: MediaQuery.of(context).size.width,
              height: dateHeight,
              child: Text(_dateText,
                  style: TextStyle(
                    color: const Color.fromARGB(255, 129, 146, 92),
                    fontSize: fontSize1,
                    fontWeight: FontWeight.bold,
                  )
              ),
            ),
          ],
        Positioned(
          top: centerY - (timeHeight / 2),
          left: 0,
          width: MediaQuery.of(context).size.width,
          height: timeHeight,
          child: Center(
            child: Text(
              _text,
              style: TextStyle(
                color: const Color.fromARGB(255, 129, 146, 92),
                fontSize: fontSize2,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _piClock({
    required double timeHeight,
    required double dateHeight,
    required double dateTimeMargin,
    required double centerY,
    required double fontSize1,
    required double fontSize2,
    required double screenWidth,
    required Color color,
    required bool watching,
  }) {
    final year = AppManager.dateFormat(_nowTime, 'yyyy年');
    final weekday = AppManager.dateFormat(_nowTime, 'E');
    final date = '${_nowTime.month}月${_nowTime.day}日（$weekday）';
    final showDate =
        !AppManager.isPiTvLayout || TvMessageSchedule.showClockDate;
    return Stack(
      children: [
        if (showDate)
          Positioned(
            top: centerY - (timeHeight / 2) - dateHeight - dateTimeMargin - 30,
            left: 0,
            width: screenWidth,
            height: dateHeight * 1.3,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    year,
                    style: TextStyle(
                      color: color,
                      fontSize: fontSize1 * 1.3,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(width: 30),
                  Text(
                    date,
                    style: TextStyle(
                      color: color,
                      fontSize: fontSize1 * 1.3,
                      fontWeight: FontWeight.bold,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        Positioned(
          top: centerY - (timeHeight / 2) + (showDate ? 20 : 0),
          left: 0,
          width: screenWidth,
          height: timeHeight,
          child: Center(
            child: Text(
              _text,
              style: TextStyle(
                color: color,
                fontSize: fontSize2,
                fontWeight: FontWeight.bold,
                height: 1.0,
              ),
            ),
          ),
        ),
        if (watching)
          Positioned(
            top: centerY + (timeHeight / 2) + (showDate ? 20 : 0),
            left: 0,
            width: screenWidth,
            child: Center(
              child: Text(
                '見守り中',
                style: TextStyle(
                  color: color,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'sans-serif',
                  height: 1.0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
