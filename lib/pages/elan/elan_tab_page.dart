import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:amiapp/pages/elan/elan_day_service_page.dart';
import 'package:amiapp/pages/elan/elan_drug_page.dart';
import 'package:amiapp/pages/elan/elan_health_page.dart';
import 'package:amiapp/pages/elan/setting/elan_setting_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:persistent_bottom_nav_bar_v2/persistent-tab-view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:amiapp/models/address_model.dart';
import 'package:amiapp/notifiers/address_notifier.dart';
import 'package:amiapp/pages/elan/elan_home_page.dart';
import 'package:amiapp/pages/elan/elan_phone_page.dart';
import 'package:amiapp/widgets/custom_nav_var_widget.dart';
import 'package:amiapp/widgets/original_image_icon_widget.dart';
import '../../helpers/widget_util.dart';
import '../../notifiers/app_notifier.dart';
import '../../services/appmanager.dart';
import '../../services/audio_service.dart';
import '../../services/socket_io_service.dart';
import 'elan_signin_page.dart';

class ElanTabPage extends StatefulWidget {
  const ElanTabPage({super.key});

  @override
  ElanTabPageState createState() => ElanTabPageState();
}

class ElanTabPageState extends State<ElanTabPage>
    with WidgetsBindingObserver, SocketIOServiceDelegate {
  bool _init = true;
  late PersistentTabController _controller;
  // bool _show = true;
  // final GlobalKey<NavigatorState> homeTabNavKey = GlobalKey<NavigatorState>();
  final GlobalKey<NavigatorState> settingTabNavKey =
      GlobalKey<NavigatorState>();
  final GlobalKey<ElanHomePageState> homeKey = GlobalKey<ElanHomePageState>();
  final GlobalKey<ElanDrugPageState> drugKey = GlobalKey<ElanDrugPageState>();
  final GlobalKey<ElanHealthPageState> healthKey =
      GlobalKey<ElanHealthPageState>();
  final GlobalKey<ElanDayServicePageState> dayServiceKey =
      GlobalKey<ElanDayServicePageState>();
  final GlobalKey<ElanPhonePageState> phoneKey =
      GlobalKey<ElanPhonePageState>();
  final GlobalKey<ElanSettingPageState> settingKey =
      GlobalKey<ElanSettingPageState>();
  int _currentIndex = 0;

  List<Widget> _pages = [];
  Timer? _pingTimer;

  SocketIOService socketservice = SocketIOService();
  AudioService audio = AudioService();

  @override
  void initState() {
    super.initState();
    print('[DEBUG PRINT] elan tab page initState');
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: [SystemUiOverlay.top, SystemUiOverlay.bottom]);
    _controller = PersistentTabController(initialIndex: 0);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    WidgetsBinding.instance.addObserver(this);
    socketservice.delegate = this;

    _pingTimer =
        Timer.periodic(const Duration(milliseconds: 30 * 1000), (Timer timer) {
      if (socketservice.isConnect()) {
        socketservice.io.emit("ping");
      }
    });
  }

  @override
  Future<void> didChangeDependencies() async {
    super.didChangeDependencies();
    print('elan tab didChangeDependencies');

    if (_init) {
      _init = false;

      var load = await AppManager.loadSetting();
      if (!load) {
        _logout();
      }

      _loadAddress();
      socketservice.connect();

      setState(() {
        _pages = _setPages();
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print(state);
    if (state == AppLifecycleState.resumed) {
      print('resumed');
      socketservice.connect();
    } else if (state == AppLifecycleState.paused) {
      print('paused');
      socketservice.disconnect();
    }
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    print('elan tab dispose');
    // socketservice.delegate = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _logout() async {
    var prefs = await SharedPreferences.getInstance();
    await prefs.setBool('login', false);
    Navigator.of(context, rootNavigator: true).pushReplacement(
        MaterialPageRoute(builder: (context) => ElanSignInPage()));
  }

  void _loadAddress() {
    SharedPreferences.getInstance().then((prefs) {
      String? addressString = prefs.getString('address');
      // print(addressString);
      if (addressString != null) {
        var addressJson = json.decode(addressString);
        context.read<AddressStore>().setAddressList(addressJson);
        // var storedAddressList = Address.fromJsonList(addressJson);

        // setState(() {
        //   addressList = storedAddressList;
        // });
      }
    });
  }

  void _disconnect() {
    socketservice.disconnect();
  }

  void _tabItemSelected(index) {
    // if (index == 2) {
    //   var store = context.read<AddressStore>();
    //   var address = store.addressList[0];
    //   store.setCalledUser(address);
    // }
    if (index == 0) {
      homeKey.currentState?.updateAppBar();
    } else if (index == 1) {
      drugKey.currentState?.reload();
    } else if (index == 2) {
      healthKey.currentState?.reload();
    } else if (index == 4) {
      dayServiceKey.currentState?.reload();
    }
    if (index == 5) {
      _disconnect();
    } else {
      socketservice.connect();
      if (settingKey.currentState != null) {
        var state = settingKey.currentState!;
        if (Navigator.of(state.context).canPop()) {
          print('setting pop');
          Navigator.of(state.context).popUntil((route) => route.isFirst);
        }
      }
    }
    if (index != 3) {
      _currentIndex = index;
    }
    if (index == 3) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
    setState(() {
      _controller.index = index;
    });
  }

  void selectTabIndex(index) {
    if (settingKey.currentState == null) {
      print('set to user list ');
    } else {
      print('to user list ');
      settingKey.currentState?.toUserListPage();
    }

    _tabItemSelected(index);
  }

  void closePhonePage() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    setState(() {
      _controller.index = 0; //_currentIndex;
    });
  }

  void receiveCall(Address address) {
    phoneKey.currentState?.selectAddress(address);
  }

  void _setAddressStatus(udid, status) {
    context.read<AddressStore>().setAddressStatus(udid, status);
  }

  void toProfileImage() {
    AppManager.toPage = 'ElanUserListPage';
    selectTabIndex(5);
  }

  List<Widget> _setPages() {
    return <Widget>[
      ElanHomePage(key: homeKey, tabPageState: this),
      ElanDrugPage(key: drugKey, tabPageState: this),
      ElanHealthPage(key: healthKey, tabPageState: this),
      ElanPhonePage(key: phoneKey, tabPageState: this),
      ElanDayServicePage(key: dayServiceKey, tabPageState: this),
      ElanSettingPage(key: settingKey),
    ];
  }

  List<PersistentBottomNavBarItem> _navBarsItems() {
    var items = [
      {'image': 'house3.png', 'title': 'HOME'},
      {'image': 'drug3.png', 'title': 'おくすり'},
      {'image': 'heart3.png', 'title': 'けんこう'},
      {'image': 'phone3.png', 'title': 'でんわ'},
      {'image': 'day3.png', 'title': 'デイ'},
      {'image': 'spana.png', 'title': '設定'},
    ];
    List<PersistentBottomNavBarItem> navbarItems = [];
    for (var item in items) {
      navbarItems.add(PersistentBottomNavBarItem(
          icon: OriginalImageIconWidget(
            AssetImage('assets/images/bottom_navi/${item['image']!}'),
            semanticLabel: item['title'],
          ),
          inactiveColorPrimary: Colors.grey,
          activeColorPrimary: const Color(0xff296934),
          title: item['title']));
    }
    return navbarItems;
  }

  @override
  Widget build(BuildContext context) {
    final AddressStore addressStore = Provider.of<AddressStore>(context);

    return Scaffold(
      body: _pages.isEmpty
          ? Container()
          : Stack(
              children: [
                PersistentTabView.custom(
                  context,
                  controller: _controller,
                  itemCount: _pages.length,
                  backgroundColor: WidgetUtil.primaryBG,
                  screens: _pages,
                  navBarHeight:
                      _controller.index == 3 ? 0 : kBottomNavigationBarHeight,
                  customWidget: (navBarEssentials) => CustomNavBarWidget(
                    items: _navBarsItems(),
                    selectedIndex: _controller.index,
                    onItemSelected: (index) {
                      _tabItemSelected(index);
                    },
                  ),
                ),
                if (addressStore.calledUser != null && _controller.index != 3)
                  GestureDetector(
                    onTap: () {
                      if (AppManager.selectUser != null) {
                        if (AppManager.selectUser!.id ==
                            addressStore.calledUser!.id) {
                          print('called user is selected');
                          return;
                        }
                      }
                      if (phoneKey.currentState == null) {
                        print('phonkey state is null');
                        addressStore.setSelectUser(addressStore.calledUser);
                      } else {
                        phoneKey.currentState!
                            .selectAddress(addressStore.calledUser!);
                      }
                      setState(() {
                        _controller.index = 3;
                      });
                    },
                    child: Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          color: Colors.black,
                          width: 160,
                          height: 30,
                          child: Text(
                            addressStore.calledUser!.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child:
                              Image.asset('assets/images/status/addr_call.png'),
                        ),
                      ]),
                    ),
                  ),
              ],
            ),
    );
  }

  @override
  void onConnect() {
    print('elan connect');
    var appStore = context.read<AppStore>();
    if (appStore.connect) {
      return;
    }
    var useType = "0";
    if (AppManager.settings["DISPTYPE"] == '2') {
      useType = '1';
    }

    socketservice.delegatorLogin(useType);
  }

  @override
  void onDisConnect() {
    print('disconnect');
    var appStore = context.read<AppStore>();
    appStore.setConnect(false);
  }

  @override
  void onAppMessage(data) {
    String message = data['message'];
    print('elan tab socket message $message');
    if (message == 'from_server') {
      if (data['productName'] == '%logined') {
        // AppManager.toast("ログイン済のアカウントです。");
        return;
      }
      socketservice.io
          .emit("clients_status", [AppManager.settings['addressGroup']]);
      var appStore = context.read<AppStore>();
      appStore.setConnect(true);
    } else if (message == 'clients_status') {
      var statuses = data['data'];
      statuses.forEach((udid, value) {
        _setAddressStatus(udid, value['status']);
      });
    } else if (message == 'login') {
      if (data['info']['client']['udid'] != null) {
        _setAddressStatus(
            data['info']['client']['udid'], data['info']['client']['status']);
      }
    } else if (message == 'status_change') {
      if (data["info"]["MYID"] != null && data["info"]["STATUS"] != null) {
        var addressStore = context.read<AddressStore>();
        var udid = data["info"]["MYID"];
        final address = addressStore.find(udid);
        if (address != null) {
          if (address.call == 1) {
            audio.stopRingtone();
            addressStore.setCall(udid, 0);
            addressStore.setCalledUser(null);
          }
        }
        _setAddressStatus(udid, data["info"]["STATUS"]);
      }
    } else if (message == 'call') {
      if (AppManager.status == AppStatus.Call ||
          AppManager.status == AppStatus.Talk ||
          AppManager.status == AppStatus.Multi ||
          AppManager.status == AppStatus.MultiToTalk) {
        return;
      }
      if (data["info"]["udid"] == null) {
        return;
      }
      var udid = data["info"]["udid"];
      var addressStore = context.read<AddressStore>();
      var address = addressStore.find(udid);
      if (address == null) {
        return;
      }
      addressStore.setCall(udid, 1);
      if (AppManager.appsettings["AUTO_RECEIVE"] == '1') {
        if (AppManager.selectUser == null) {
          AppManager.autoReceiveId = address.id;
          receiveCall(address);
        }
        return;
      }
      if (AppManager.selectUser?.id != address.id) {
        addressStore.setCalledUser(address);
      }
      audio.ringtone();
    } else if (message == 'call_cancel') {
      if (data["udid"] == null) {
        return;
      }
      var addressStore = context.read<AddressStore>();
      addressStore.setCall(data["udid"], 0);
      addressStore.setCalled(data["udid"], 1);
      if (addressStore.calledUser?.id == data["udid"]) {
        addressStore.setCalledUser(null);
      }
      audio.stopRingtone();
    }
  }

  @override
  void onMessage(data) {
    // TODO: implement onMessage
  }

  @override
  void onTalkMessage(data) {
    // TODO: implement onTalkMessage
  }
}
