import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:amiapp/services/appmanager.dart';

class ClockWidget extends StatefulWidget {
  const ClockWidget({super.key});


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
}
