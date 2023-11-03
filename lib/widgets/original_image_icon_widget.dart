import 'package:flutter/material.dart';

class OriginalImageIconWidget extends ImageIcon {
  const OriginalImageIconWidget(
      ImageProvider image, {
        Key? key,
        double? size,
        Color? color,
        String? semanticLabel,
      }) : super(image,
      key: key, size: size, color: color, semanticLabel: semanticLabel);

  @override
  Widget build(BuildContext context) {
    final IconThemeData iconTheme = IconTheme.of(context);
    final double? iconSize = size ?? iconTheme.size;

    return Semantics(
      label: semanticLabel,
      child: ExcludeSemantics(
        child: Image(
          image: image!,
          width: iconSize,
          height: iconSize,
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          excludeFromSemantics: true,
          // color属性は設定しない
        ),
      ),
    );
  }
}