import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:amiapp/models/address_model.dart';
import '../services/appmanager.dart';
import '../services/sensor.dart';

class StaffUtil {

  static Widget managerAddressCell(Address address, Function selectAddress) {
    String liveText = '';
    Uint8List bytes = Uint8List(0);
    var baseImageName = 'assets/images/status/addr.png';
    if (address.sensors.isNotEmpty) {
      print("biosliv image");
      var sensorImage = SensorService.biosilverImageName(address.sensors);
      if (sensorImage.isNotEmpty) {
        baseImageName = sensorImage;
      }
    }
    else if (address.sensor.isNotEmpty) {
      // var sensorImage = SensorService.imageName(address.sensor);
      // if (sensorImage.length > 0) {
      //   imageName = sensorImage;
      // }
    }
    else if (address.userType == 'S') {
      baseImageName = 'assets/images/status/dummy.png';
    }

    var imageName = '';
    if (address.call == 1) {
      imageName = 'assets/images/status/addr_call.png';
    }
    else if (address.called == 1) {
      imageName = 'assets/images/status/addr_called.png';
    }
    else if (address.supported == 1) {
      imageName = 'assets/images/status/addr_supported.png';
    }
    else if (address.status == 0 || address.status == 1) {
      if (address.sensors.isNotEmpty) {
        print("biosliv image");
        var sensorImage = SensorService.biosilverImageName(address.sensors);
        if (sensorImage.isNotEmpty) {
          imageName = sensorImage;
        }
      }
      else if (address.sensor.isNotEmpty) {
        // var sensorImage = SensorService.imageName(address.sensor);
        // if (sensorImage.length > 0) {
        //   imageName = sensorImage;
        // }
      }
      else if (address.photo.isNotEmpty) {
        // var photo = address.photo;
        // var base64Pos = photo.indexOf('base64,');
        // if (base64Pos >= 0) {
        //   photo = photo.substring(base64Pos + 'base64,'.length);
        //   bytes = base64Decode(photo);
        // }
      }
      else if (address.userType == 'S') {
        imageName = 'assets/images/status/addr_staff.png';
      }
    }
    else if (address.status == 2 ||
        address.status == 3 ||
        address.status == 4 ||
        address.status == 5) {
      imageName = 'assets/images/status/addr_talk.png';
    }
    else if (address.status == 9) {
      liveText = 'LIVE';
      if (address.liveimage.isNotEmpty) {
        bytes = base64Decode(address.liveimage);
      }
    }
    else if (address.status == -1) {
      if (address.sensors.isNotEmpty) {
        print("biosliv image");
        var sensorImage = SensorService.biosilverImageName(address.sensors);
        if (sensorImage.isNotEmpty) {
          imageName = sensorImage;
        }
      } else if (address.sensor.isNotEmpty) {
        // var sensorImage = SensorService.imageName(address.sensor);
        // if (sensorImage.length > 0) {
        //   imageName = sensorImage;
        // }
      }
    }

    var imageWidget = (imageName.isEmpty && bytes.isNotEmpty) ? Image.memory(
      bytes,
      fit: BoxFit.cover,
      gaplessPlayback: true,
    ) :
    Image.asset(
      imageName.isEmpty ? baseImageName : imageName,
      fit: BoxFit.cover,
      gaplessPlayback: true,
    );



    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: const Color.fromARGB(255, 80, 80, 80),
          height: 21,
          child: Text(
            address.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white,
            ),
          ),
        ),
        Expanded(
          child: GestureDetector(
            onTap: () {
              selectAddress(address);
            },
            child: Container(
              color: const Color.fromARGB(255, 30, 30, 30),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  imageWidget,
                  Positioned(
                      top: 0,
                      left: 2.0,
                      child: Text(
                        liveText,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.red,
                        ),
                      )),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static Widget managerAddressListCell(Size size, Address address, Function selectAddress, Function talkHistoryButton, Function graphButton) {
    var textSize = 14.0;
    var textWidth = 120.0;
    var buttonHeight = 72.0;
    var buttonMinWidth = 80.0;

    if (size.width < 600) {
      textSize = 13.0;
      textWidth = 80.0;
      buttonHeight = 36.0;
      buttonMinWidth = 40.0;
    }

    var buttonWidth = buttonHeight / 3 * 4;

    var issensor1 = false;
    var issensor2 = false;
    var issensor3 = false;
    var issensor4 = false;
    if (address.userType != '5') {
      if (AppManager.appsettings['SENSOR1'] == '1') {
        issensor1 = true;
      }
      if (AppManager.appsettings['SENSOR2'] == '1') {
        issensor2 = true;
      }
      if (AppManager.appsettings['SENSOR3'] == '1') {
        issensor3 = true;
      }
      if (AppManager.appsettings['SENSOR4'] == '1') {
        issensor4 = true;
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: Color.fromARGB(255, 30, 30, 30),
        border: Border(
          bottom: BorderSide(color: Color.fromARGB(255, 80, 80, 80)),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(
            width: textWidth,
            child: Text(
              address.name,
              style: TextStyle(
                fontSize: textSize,
                color: Colors.white,
              ),
            ),
          ),
          Center(
            child: ButtonTheme(
              minWidth: buttonMinWidth,
              height: 30.0,
              child: ElevatedButton(
                child: Text("履歴"),
                // color: Colors.grey,
                // textColor: Colors.white,
                onPressed: () async {
                  talkHistoryButton(address);
                },
              ),
            ),
          ),
          Container(width: 5.0),
          Center(
              child: GestureDetector(
                child: Image.asset(
                  'assets/images/service/sc_video.png',
                  width: buttonWidth,
                  height: buttonHeight,
                ),
                onTap: () {
                  selectAddress(address);
                },
              )),
          Container(width: 5.0),
          issensor2
              ? Center(
            child: GestureDetector(
              child: Image.asset(
                'assets/images/service/sc_pir.png',
                width: buttonWidth,
                height: buttonHeight,
              ),
              onTap: () {
                graphButton(address, "2");
              },
            ),
          )
              : Container(width: buttonWidth),
          Container(width: 5.0),
          issensor1
              ? Center(
              child: GestureDetector(
                child: Image.asset(
                  'assets/images/service/sc_alert_H.png',
                  width: buttonWidth,
                  height: buttonHeight,
                ),
                onTap: () {
                  graphButton(address, "1");
                },
              ))
              : Container(width: buttonWidth),
          Container(width: 5.0),
          issensor3
              ? Center(
              child: GestureDetector(
                child: Image.asset(
                  'assets/images/service/sc_flame.png',
                  width: buttonWidth,
                  height: buttonHeight,
                ),
                onTap: () {
                  graphButton(address, "3");
                },
              ))
              : Container(width: buttonWidth),
          issensor4
              ? Center(
              child: GestureDetector(
                child: Image.asset(
                  'assets/images/service/sc_co2.png',
                  width: buttonWidth,
                  height: buttonHeight,
                ),
                onTap: () {
                  graphButton(address, "4");
                },
              ))
              : Container(width: buttonWidth),
        ],
      ),
    );
  }
}