import 'package:amiapp/helpers/widget_util.dart';
import 'package:flutter/material.dart';
import 'package:amiapp/pages/staff/staff_talk_page.dart';
import 'package:amiapp/services/appmanager.dart';

class SensorViewWidget extends StatefulWidget {
  SensorViewWidget({required Key key}) : super(key: key);

  @override
  SensorViewWidgetState createState() => SensorViewWidgetState();
}

class SensorViewWidgetState extends State<SensorViewWidget> {
  late StaffTalkViewPageState staffTalkPageState;

  @override
  void initState() {
    super.initState();
    staffTalkPageState = context.findAncestorStateOfType<StaffTalkViewPageState>()!;
  }

  List<Widget> _sensors() {
    final Size size = MediaQuery.of(context).size;
    var textWidth = 120.0;


    List<Widget> widgets = [];
    if (AppManager.appsettings['SENSOR1'] == '1') {
      widgets.add(Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: textWidth,
            color: Colors.grey,
            padding: EdgeInsets.all(8.0),
            child: Text(
              'レガーメ',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
          Container(width: 20.0),
          GestureDetector(
            child: Image.asset(
              'assets/images/service/sc_alert_H.png',
              width: textWidth,
              height: textWidth / 3 * 2,
            ),
            onTap: () {
              staffTalkPageState.graphButton("1");
            },
          ),
        ],
      ));
      widgets.add(Container(height: 10.0));
    }

    if (AppManager.appsettings['SENSOR2'] == '1') {
      widgets.add(Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: textWidth,
            color: Colors.grey,
            padding: EdgeInsets.all(8.0),
            child: Text(
              '人感センサー',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
          Container(width: 20.0),
          GestureDetector(
            child: Image.asset(
              'assets/images/service/sc_pir.png',
              width: textWidth,
              height: textWidth / 3 * 2,
            ),
            onTap: () {
              staffTalkPageState.graphButton("2");
            },
          ),
        ],
      ));
      widgets.add(Container(height: 10.0));
    }

    if (AppManager.appsettings['SENSOR3'] == '1') {
      widgets.add(Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: textWidth,
            color: Colors.grey,
            padding: EdgeInsets.all(8.0),
            child: Text(
              '炎センサー',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
          Container(width: 20.0),
          GestureDetector(
            child: Image.asset(
              'assets/images/service/sc_flame.png',
              width: textWidth,
              height: textWidth / 3 * 2,
            ),
            onTap: () {
              staffTalkPageState.graphButton("3");
            },
          ),
        ],
      ));
    }

    if (AppManager.appsettings['SENSOR4'] == '1') {
      widgets.add(Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: textWidth,
            color: Colors.grey,
            padding: EdgeInsets.all(8.0),
            child: Text(
              'CO2センサー',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
          Container(width: 20.0),
          GestureDetector(
            child: Image.asset(
              'assets/images/service/sc_co2.png',
              width: textWidth,
              height: textWidth / 3 * 2,
            ),
            onTap: () {
              staffTalkPageState.graphButton("4");
            },
          ),
        ],
      ));
    }

    if (AppManager.appsettings['SENSOR8'] == '1') {
      widgets.add(Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: textWidth,
            color: Colors.grey,
            padding: EdgeInsets.all(8.0),
            child: Text(
              '血圧計',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
          Container(width: 20.0),
          GestureDetector(
            child: Image.asset(
              'assets/images/service/sc_vital.png',
              width: textWidth,
              height: textWidth / 3 * 2,
            ),
            onTap: () {
              staffTalkPageState.graphButton("8");
            },
          ),
        ],
      ));
    }

    if (AppManager.appsettings['SENSOR9'] == '1') {
      widgets.add(Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Container(
            width: textWidth,
            color: Colors.grey,
            padding: EdgeInsets.all(8.0),
            child: Text(
              'パルスオキシメーター',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 20.0),
          GestureDetector(
            child: Image.asset(
              'assets/images/service/sc_spo2.png',
              width: textWidth,
              height: textWidth / 3 * 2,
            ),
            onTap: () {
              staffTalkPageState.graphButton("9");
            },
          ),
        ],
      ));
    }

    return widgets;
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;

    return Container(
      color: const Color.fromARGB(160, 0, 0, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 80.0),
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(
              vertical: 10.0, horizontal: 8.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: WidgetUtil.basicText('●アイコンをタップして詳細ページへ'),
              ),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: _sensors(),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: WidgetUtil.normalButton('閉じる', () {
                  staffTalkPageState.hideSensorView();
                }, width: 140, height: 30, primaryColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}