import 'package:flutter/material.dart';

class AppStore with ChangeNotifier {
  bool connect = false;

  void setConnect(value) {
    connect = value;
    notifyListeners();
  }
}