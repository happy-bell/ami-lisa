import 'package:flutter/material.dart';

class SimplePageRoute extends PageRouteBuilder {
  final Widget page;
  final RouteSettings settings;
  SimplePageRoute({required this.page, required this.settings})
      : super(
    pageBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        ) {
      return page;
    },
    transitionsBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        Widget page,
        ) {
      return SlideTransition(
        position: Tween<Offset>(
          begin: Offset.zero,
          end: Offset.zero,
        ).animate(animation),
        child: page,
      );
    },
  );
}