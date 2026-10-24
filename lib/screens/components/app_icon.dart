import 'package:flutter/material.dart';

class AppIcon extends StatelessWidget {
  final double size;
  final double borderRadius;
  final String semanticLabel;

  const AppIcon({
    Key? key,
    required this.size,
    this.borderRadius = 16,
    this.semanticLabel = 'JMComic3 Mod',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'lib/assets/app_icon_background.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
            ),
            Image.asset(
              'lib/assets/app_icon_foreground.png',
              fit: BoxFit.cover,
              filterQuality: FilterQuality.high,
              semanticLabel: semanticLabel,
            ),
          ],
        ),
      ),
    );
  }
}
