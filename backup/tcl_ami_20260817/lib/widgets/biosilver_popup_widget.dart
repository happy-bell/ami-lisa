import 'package:flutter/material.dart';

class BiosilverPopupWidget extends StatefulWidget {
  final String udid;
  final List<dynamic> alerts;
  final Function onClose;

  const BiosilverPopupWidget({super.key, required this.udid, required this.alerts, required this.onClose});

  @override
  _BiosilverPopupWidgetState createState() => _BiosilverPopupWidgetState();
}

class _BiosilverPopupWidgetState extends State<BiosilverPopupWidget> {
  late String udid;
  late List<dynamic> alerts;

  @override
  void initState() {
    super.initState();
    udid = widget.udid;
    alerts = widget.alerts;
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var screenWidth = MediaQuery.of(context).size.width;
    var screenHeight = MediaQuery.of(context).size.height;

    var width = screenWidth - 20;
    if (width > 528) {
      width = 528;
    }
    var imageWidth = (width - 16 - 16) / 3;
    var imageHeight = imageWidth / 480 * 428;
    var left = (screenWidth - width) / 2;
    var imageNames = [
      "assets/images/sensor/bs_a4_off.png",
      "assets/images/sensor/bs_a1_1_off.png",
      "assets/images/sensor/bs_a8_off.png",
      "assets/images/sensor/bs_a3_1_off.png",
      "assets/images/sensor/bs_a2_1_off.png",
      "assets/images/sensor/bs_a1_0_off.png",
      "assets/images/sensor/bs_a2_0_off.png",
      "assets/images/sensor/bs_a6_off.png",
      "assets/images/sensor/bs_a3_0_off.png",
    ];

    if (alerts.contains("a4")) { imageNames[0] = "assets/images/sensor/bs_a4_on.png"; }
    if (alerts.contains("a1_1")) { imageNames[1] = "assets/images/sensor/bs_a1_1_on.png"; }
    if (alerts.contains("a8")) { imageNames[2] = "assets/images/sensor/bs_a8_on.png"; }
    if (alerts.contains("a3_1")) { imageNames[3] = "assets/images/sensor/bs_a3_1_on.png"; }
    if (alerts.contains("a2_1")) { imageNames[4] = "assets/images/sensor/bs_a2_1_on.png"; }
    if (alerts.contains("a1_0")) { imageNames[5] = "assets/images/sensor/bs_a1_0_on.png"; }
    if (alerts.contains("a2_0")) { imageNames[6] = "assets/images/sensor/bs_a2_0_on.png"; }
    if (alerts.contains("a6")) { imageNames[7] = "assets/images/sensor/bs_a6_on.png"; }
    if (alerts.contains("a3_0")) { imageNames[8] = "assets/images/sensor/bs_a3_0_on.png"; }

    return Stack(
      children: <Widget>[
        Positioned(
          top: 0,
          left: 0,
          width: screenWidth,
          height: screenHeight,
          child: Opacity(
            opacity: 0.5,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
              ),
            ),
          ),
        ),
        Positioned(
          top: 100,
          left: left,
          child: Container(
            width: width,
            height: width * 1.1,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(width: imageWidth, height: imageHeight, child: Image.asset(imageNames[0], fit: BoxFit.cover,)),
                    SizedBox(width: 8,),
                    SizedBox(width: imageWidth, height: imageHeight, child: Image.asset(imageNames[1], fit: BoxFit.cover,)),
                    SizedBox(width: 8,),
                    SizedBox(width: imageWidth, height: imageHeight, child: Image.asset(imageNames[2], fit: BoxFit.cover,))
                  ],
                ),
                SizedBox(height: 8,),
                Row(
                  children: [
                    SizedBox(width: imageWidth, height: imageHeight, child: Image.asset(imageNames[3], fit: BoxFit.cover,)),
                    SizedBox(width: 8,),
                    SizedBox(width: imageWidth, height: imageHeight, child: Image.asset(imageNames[4], fit: BoxFit.cover,)),
                    SizedBox(width: 8,),
                    SizedBox(width: imageWidth, height: imageHeight, child: Image.asset(imageNames[5], fit: BoxFit.cover,))
                  ],
                ),
                SizedBox(height: 8,),
                Row(
                  children: [
                    SizedBox(width: imageWidth, height: imageHeight, child: Image.asset(imageNames[6], fit: BoxFit.cover,)),
                    SizedBox(width: 8,),
                    SizedBox(width: imageWidth, height: imageHeight, child: Image.asset(imageNames[7], fit: BoxFit.cover,)),
                    SizedBox(width: 8,),
                    SizedBox(width: imageWidth, height: imageHeight, child: Image.asset(imageNames[8], fit: BoxFit.cover,))
                  ],
                ),
                SizedBox(height: 20,),
                Center(
                  child: SizedBox(
                    width: imageWidth,
                    height: 36,
                    child: TextButton(
                      style: ElevatedButton.styleFrom(
                        // backgroundColor: MyColors.btnGreen,
                        // onPrimary: Colors.white,
                      ),
                      onPressed: () async {
                        widget.onClose();
                      },
                      child: const Text('閉じる'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
