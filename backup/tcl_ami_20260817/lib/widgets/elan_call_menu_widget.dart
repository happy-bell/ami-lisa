import 'package:flutter/material.dart';
import 'package:amiapp/services/appmanager.dart';

import '../pages/elan/elan_call_page.dart';

class ElanCallMenuWidget extends StatefulWidget {
  const ElanCallMenuWidget({required Key key}) : super(key: key);

  @override
  ElanCallMenuWidgetState createState() => ElanCallMenuWidgetState();
}

class ElanCallMenuWidgetState extends State<ElanCallMenuWidget> {
  bool _showsubmenu = false;
  late ElanCallPageState elanCallPageState;

  bool _talking = false;
  bool _callButtonIsEnabled = true;
  bool _callendIsEnabled = false;
  bool _holdIsEnabled = false;
  bool _myCameraIsEnabled = false;
  bool _otherCaptureIsEnabled = false;
  bool _otherCameraIsEnabled = false;
  bool _recordIsEnabled = false;
  bool _recordEndIsEnabled = false;
  bool _threewayIsEnabled = false;
  bool _addCallIsEnabled = false;
  bool _safetyCheck = false;
  bool _otherView = true;
  bool _sensorEnabled = false;

  @override
  void initState() {
    super.initState();
    elanCallPageState = context.findAncestorStateOfType<ElanCallPageState>()!;

    if (AppManager.appsettings['SENSOR1'] == '1' ||
        AppManager.appsettings['SENSOR2'] == '1' ||
        AppManager.appsettings['SENSOR3'] == '1' ||
        AppManager.appsettings['SENSOR4'] == '1') {
      _sensorEnabled = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = MediaQuery.of(context).size;
    final viewInsets = MediaQuery.of(context).viewInsets;
    final viewPadding = MediaQuery.of(context).padding;
    final bottomOffset = viewInsets.bottom + viewPadding.bottom;
    print('elan call menu build');
    print(size);
    _setButtonState();
    var button1Width = size.width / 4;
    if (button1Width > 168) {
      button1Width = 168;
    }
    final button1Height = button1Width / 335 * 182;
    final button2Width = button1Height / 182 * 228;
    final button3Height = button2Width / 239 * 130;
    print(button2Width);
    final anminModeFlg = AppManager.appsettings['ANMINMODEFLG'];

    return AppManager.safetyCheckId.isNotEmpty
        ? Positioned(
      bottom: bottomOffset,
      left: 0,
      width: size.width,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          MaterialButton(
            onPressed: () {
              elanCallPageState.safetyCheckEndButton();
            },
            color: Colors.red,
            textColor: Colors.white,
            padding: const EdgeInsets.all(8),
            shape: const CircleBorder(),
            child: const Icon(
              Icons.clear,
              size: 16,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12.0),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
              decoration: BoxDecoration(
                color: Colors.yellow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '安静目視中',
                style: TextStyle(
                  fontSize: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    )
        : Positioned(
      bottom: (_showsubmenu ? 0.0 : -1 * (button1Height + button3Height)) + bottomOffset,
      left: 10,
      width: size.width,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              Opacity(
                opacity: _callButtonIsEnabled ? 1.0 : 0.5,
                child: GestureDetector(
                  onTap: () {
                    if (_callButtonIsEnabled) {
                      elanCallPageState.callButton();
                    }
                  },
                  child: Image.asset(
                    'assets/images/talk/btn-calling.png',
                    width: button1Width,
                    height: button1Height,
                  ),
                ),
              ),
              Opacity(
                opacity: _callendIsEnabled ? 1.0 : 0.5,
                child: GestureDetector(
                  child: Image.asset(
                    'assets/images/talk/btn-callend.png',
                    width: button1Width,
                    height: button1Height,
                  ),
                  onTap: () {
                    if (_callendIsEnabled) {
                      elanCallPageState.callEndButton();
                    }
                  },
                ),
              ),
              GestureDetector(
                child: Image.asset(
                  'assets/images/talk/btn-menu.png',
                  width: button2Width,
                  height: button1Height,
                ),
                onTap: () {
                  setState(() {
                    _showsubmenu = !_showsubmenu;
                  });
                },
              ),
            ],
          ),
          Opacity(
            opacity: _showsubmenu ? 1.0 : 0.0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Opacity(
                  opacity: _otherView && _sensorEnabled ? 1.0 : 0.5,
                  child: GestureDetector(
                    child: Image.asset(
                      'assets/images/talk/btn-sensor.png',
                      width: button1Width,
                      height: button1Height,
                    ),
                    onTap: () {
                      print('sensor');print(_otherView ? 'o' : 'oo');print(_sensorEnabled ? 's' : 'ss');
                      if (_otherView && _sensorEnabled) {
                        print('sensor2');
                        // TODO: implement _sensorButton
                        // staffTalkPageState._sensorButton();
                      }
                    },
                  ),
                ),
                Opacity(
                  opacity: (_otherView && anminModeFlg == '1') ? 1.0 : 0.5,
                  child: GestureDetector(
                    onTap: _otherView && anminModeFlg == '1' ? elanCallPageState.safetyCheckButton : null,
                    child: Image.asset(
                      'assets/images/talk/btn-watch.png',
                      width: button1Width,
                      height: button1Height,
                    ),
                  ),
                ),
                Opacity(
                  opacity: _holdIsEnabled ? 1.0 : 0.5,
                  child: GestureDetector(
                    onTap: _holdIsEnabled ? elanCallPageState.holdButton : null,
                    child: Image.asset(
                      'assets/images/talk/btn-hold.png',
                      width: button2Width,
                      height: button1Height,
                    ),
                  ),
                ),
                if (1 == 0)
                  GestureDetector(
                    child: Image.asset(
                      'assets/images/talk/btn-rms.png',
                      width: button2Width,
                      height: button1Height,
                    ),
                    onTap: () {
                      // TODO: implement _rmsButton
                      // staffTalkPageState?._rmsButton();
                    },
                  ),
              ],
            ),
          ),
          Opacity(
            opacity: _showsubmenu ? 1.0 : 0.0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Opacity(
                  opacity: AppManager.isMute ? 0.5 : 1.0,
                  child: GestureDetector(
                    onTap: elanCallPageState.muteButton,
                    child: Image.asset(
                      'assets/images/talk/btn-mic-mute.png',
                      width: button2Width,
                      height: button3Height,
                    ),
                  ),
                ),
                Opacity(
                  opacity: AppManager.isVideoMute ? 0.5 : 1.0,
                  child: GestureDetector(
                    onTap: elanCallPageState.videoMuteButton,
                    child: Image.asset(
                      'assets/images/talk/btn-cam-off.png',
                      width: button2Width,
                      height: button3Height,
                    ),
                  ),
                ),
                Opacity(
                  opacity: _callendIsEnabled ? 1.0 : 0.5,
                  child: GestureDetector(
                    onTap: _callendIsEnabled ? elanCallPageState.addCallButton : null,
                    child: Image.asset(
                      'assets/images/talk/btn-addcall.png',
                      width: button2Width,
                      height: button3Height,
                    ),
                  ),
                ),
                Opacity(
                  opacity: _threewayIsEnabled ? 1.0 : 0.5,
                  child: GestureDetector(
                    onTap: _threewayIsEnabled ? elanCallPageState.threewayButton : null,
                    child: Image.asset(
                      'assets/images/talk/btn-3way.png',
                      width: button2Width,
                      height: button3Height,
                    ),
                  ),
                ),
                Opacity(
                  opacity: !_otherView ? 0.5 : 1.0,
                  child: GestureDetector(
                    onTap: _otherView ? elanCallPageState.albumButton : null,
                    child: Image.asset(
                      'assets/images/talk/btn-album.png',
                      width: button2Width,
                      height: button3Height,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _setButtonState() {
    var call = 0;

    bool talking = false;
    bool callend = true;
    var hold = false;
    var myCamera = false;
    var otherCapture = false;
    var otherCamera = false;
    var record = false;
    var recordEnd = false;
    var threeway = false;
    var addCall = false;
    var callButtonIsEnabled = true;
    var safetyCheck = false;
    var otherView = true;

    if (AppManager.holdId.isNotEmpty) {
      if (AppManager.selectUser!.id == AppManager.holdId) {
        addCall = true;
        hold = true;
      } else {
        if (AppManager.status == AppStatus.Talk) {
          threeway = true;
        }
      }
    }

    if (AppManager.status == AppStatus.None && call == 0) {
      // callend = false;
      safetyCheck = true;
      callend = false;
    }

    if (AppManager.selectUser!.call == 1) {
      callend = true;
    }

    if (AppManager.status == AppStatus.Talk ||
        AppManager.status == AppStatus.Multi ||
        AppManager.status == AppStatus.MultiToTalk) {
      talking = true;
    }

    if (AppManager.status == AppStatus.Talk) {
      hold = true;
      myCamera = true;
      otherCamera = true;
      addCall = false;
      otherCapture = true;
      if (AppManager.isRecording) {
        recordEnd = true;
      } else {
        record = true;
      }
    }

    if (AppManager.status == AppStatus.Call ||
        AppManager.status == AppStatus.Talk ||
        AppManager.status == AppStatus.Multi ||
        AppManager.status == AppStatus.Response ||
        AppManager.status == AppStatus.MultiToTalk ||
        AppManager.status == AppStatus.Holded) {
      callButtonIsEnabled = false;
    }

    if (AppManager.status == AppStatus.Call ||
        AppManager.status == AppStatus.Talk ||
        AppManager.status == AppStatus.Multi ||
        AppManager.status == AppStatus.MultiToTalk ||
        AppManager.status == AppStatus.Holded) {
      otherView = false;
    }

    _callendIsEnabled = callend;
    _talking = talking;
    _holdIsEnabled = hold;
    _myCameraIsEnabled = myCamera;
    _otherCaptureIsEnabled = otherCapture;
    _otherCameraIsEnabled = otherCamera;
    _recordIsEnabled = record;
    _recordEndIsEnabled = recordEnd;
    _threewayIsEnabled = threeway;
    _addCallIsEnabled = addCall;
    _callButtonIsEnabled = callButtonIsEnabled;
    _safetyCheck = safetyCheck;
    _otherView = otherView;
  }
}