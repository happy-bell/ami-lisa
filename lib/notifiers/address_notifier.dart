import 'package:flutter/material.dart';
import 'package:amiapp/models/address_model.dart';
import 'package:amiapp/services/appmanager.dart';

class AddressStore with ChangeNotifier {
  List<Address> addressList = [];
  bool connect = false;
  Address? calledUser;
  Address? selectUser;

  void setConnect(value) {
    connect = value;
    notifyListeners();
  }

  void setCalledUser(Address? value) {
    calledUser = value;
    notifyListeners();
  }

  void setSelectUser(Address? value) {
    selectUser = value;
    notifyListeners();
  }

  void setAddressList(addressJson) {
    var storedAddressList = Address.fromJsonList(addressJson);
    addressList = [...storedAddressList];
  }

  List<Address> managerList() {
    List<Address> data = [];
    for (var i = 0; i < addressList.length; i++) {
      if (addressList[i].type != 'manager') {
        continue;
      }
      if (addressList[i].id != AppManager.myId) {
        data.add(addressList[i]);
      }
    }
    return data;
  }

  List<Address> staffList() {
    List<Address> data = [];
    for (var i = 0; i < addressList.length; i++) {
      if (addressList[i].type == 'manager') {
        continue;
      }
      if (AppManager.selectCode.isNotEmpty && AppManager.selectCode != addressList[i].code) {
        continue;
      }
      if (addressList[i].id != AppManager.myId) {
        data.add(addressList[i]);
      }
    }
    return data;
  }

  List<List<String>> list(type) {
    List<List<String>> data = [];
    for (var i = 0; i < addressList.length; i++) {
      if (addressList[i].userType == type) {
        data.add([addressList[i].id, addressList[i].name]);
      }
    }
    return data;
  }

  Address? find(udid) {
    var index = _findAddress(udid);
    if (index >= 0) {
      return addressList[index];
    }

    return null;
  }

  Address? findManager(udid) {
    final index = _findManagerAddress(udid);
    if (index < 0) {
      return null;
    }
    return addressList[index];
  }

  String managerName(code) {
    final index = addressList.indexWhere((item) => item.code == code && item.type == 'manager');
    if (index >= 0) {
      final address = addressList[index];
      return address.name;
    }
    return '';
  }

  _findAddress(udid) {
    final index = addressList.indexWhere((item) => item.id == udid);
    return index;
  }

  _findStaffAddress(udid) {
    final index = addressList.indexWhere((item) => item.id == udid && item.userType == 'S');
    return index;
  }

  _findManagerAddress(udid) {
    final index = addressList.indexWhere((item) => item.id == udid && item.type == 'manager');
    return index;
  }

  findAddress(udid) {
    return _findAddress(udid);
  }

  clear() {
    for (var i = 0; i < addressList.length; i++) {
      addressList[i].status = -1;
      addressList[i].call = 0;
      addressList[i].called = 0;
      addressList[i].liveimage = '';
      addressList[i].sensor = '';
    }
    notifyListeners();
  }

  setAddressStatus(udid, status) {
    final index = _findAddress(udid);
    print('setAddressStatus   $index');
    if (index < 0) {
      return;
    }

    setAddressStatusManager(udid, status);
    print('status change $udid => $status');
    addressList[index].status = int.parse(status);
    notifyListeners();
  }

  setAddressStatusManager(udid, status) {
    final address = find(udid)!;
    if (address.userType == 'S') {
      return;
    }
    final index = _findAddress('manager_${address.code}');
    if (index < 0) {
      return;
    }

    print('manager status change $udid => $status');
    addressList[index].status = int.parse(status);
  }

  setCall(udid, value) {
    final index = _findAddress(udid);
    if (index < 0) {
      return;
    }

    setCallManager(udid, value);
    print('set call $udid => $value');
    addressList[index].call = value;
    notifyListeners();
  }

  setCallManager(udid, value) {
    final address = find(udid)!;
    if (address.userType == 'S') {
      return;
    }
    final index = _findAddress('manager_${address.code}');
    if (index < 0) {
      return;
    }
    addressList[index].call = value;
  }

  setCalled(udid, value) {
    final index = _findAddress(udid);
    if (index < 0) {
      return;
    }

    setCalledManager(udid, value);
    print('set called $udid => $value');
    addressList[index].called = value;
    notifyListeners();
  }

  setCalledManager(udid, value) {
    final address = find(udid)!;
    if (address.userType == 'S') {
      return;
    }
    final index = _findAddress('manager_${address.code}');
    if (index < 0) {
      return;
    }
    addressList[index].called = value;

  }

  setSupported(udid, value) {
    final index = _findAddress(udid);
    if (index < 0) {
      return;
    }

    print('set supported $udid => $value');
    addressList[index].supported = value;
    notifyListeners();
  }

  setLiveImage(udid, image) {
    final index = _findAddress(udid);
    if (index < 0) {
      return;
    }

    addressList[index].liveimage = image;
    notifyListeners();
  }

  setSensor(udid, alert) {
    final index = _findAddress(udid);
    if (index < 0) {
      return;
    }

    addressList[index].sensor = alert;
    notifyListeners();
  }

  setSensors(udid, alerts) {
    final index = _findAddress(udid);
    if (index < 0) {
      return;
    }

    addressList[index].sensors = alerts;
    notifyListeners();
  }

}