import 'package:flutter/material.dart';
import 'package:jmcomic3/configs/versions.dart';

class UpdateDot extends StatelessWidget {
  static const defaultColor = Color(0xFFE60012);

  final double size;

  const UpdateDot({super.key, this.size = 7});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: defaultColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 1,
        ),
      ),
    );
  }
}

// 提示信息, 组件右上角的小红点
class Badged extends StatelessWidget {
  final String? badge;
  final Widget child;

  const Badged({Key? key, required this.child, this.badge}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (badge == null) {
      return child;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (badge!.isEmpty)
          const Positioned(
            top: 0,
            right: 0,
            child: UpdateDot(
              key: ValueKey('version-update-dot'),
            ),
          )
        else
          Positioned(
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(6),
              ),
              constraints: const BoxConstraints(
                minWidth: 12,
                minHeight: 12,
              ),
              child: Text(
                badge!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class VersionBadged extends StatefulWidget {
  final Widget child;

  const VersionBadged({required this.child, Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _VersionBadgedState();
}

class _VersionBadgedState extends State<VersionBadged> {
  @override
  void initState() {
    versionEvent.subscribe(_onVersion);
    super.initState();
  }

  @override
  void dispose() {
    versionEvent.unsubscribe(_onVersion);
    super.dispose();
  }

  void _onVersion(dynamic a) {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Badged(
      child: widget.child,
      badge: updatesTemporarilyDisabled || latestVersion == null ? null : "",
    );
  }
}
