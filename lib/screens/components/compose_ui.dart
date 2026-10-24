import 'package:flutter/material.dart';

// Shared declarative UI primitives for the Compose-style app shell.

class ComposeNavigationDestination {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const ComposeNavigationDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class ComposeFloatingNavigationBar extends StatelessWidget {
  final List<ComposeNavigationDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool visible;

  const ComposeFloatingNavigationBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    this.visible = true,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final showLabels = MediaQuery.textScalerOf(context).scale(10) <= 15;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 300);
    final selectedAlignment = destinations.length <= 1
        ? Alignment.center
        : Alignment(
            -1 +
                (selectedIndex.clamp(0, destinations.length - 1) * 2) /
                    (destinations.length - 1),
            0,
          );

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : const Offset(0, 1.35),
        duration: duration,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: duration,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: .97),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: .48),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: IgnorePointer(
                              child: AnimatedAlign(
                                key: const ValueKey(
                                  'compose-navigation-indicator',
                                ),
                                alignment: selectedAlignment,
                                duration: duration,
                                curve: Curves.easeOutCubic,
                                child: FractionallySizedBox(
                                  widthFactor: 1 / destinations.length,
                                  heightFactor: 1,
                                  child: Padding(
                                    padding: const EdgeInsets.all(2),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: scheme.primaryContainer
                                            .withValues(alpha: .88),
                                        borderRadius: BorderRadius.circular(23),
                                        boxShadow: [
                                          BoxShadow(
                                            color: scheme.primary
                                                .withValues(alpha: .08),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              for (var index = 0;
                                  index < destinations.length;
                                  index++)
                                Expanded(
                                  child: _ComposeNavigationItem(
                                    destination: destinations[index],
                                    selected: selectedIndex == index,
                                    showLabel: showLabels,
                                    duration: duration,
                                    onTap: () => onSelected(index),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ComposeNavigationItem extends StatelessWidget {
  final ComposeNavigationDestination destination;
  final bool selected;
  final bool showLabel;
  final Duration duration;
  final VoidCallback onTap;

  const _ComposeNavigationItem({
    required this.destination,
    required this.selected,
    required this.showLabel,
    required this.duration,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground =
        selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;

    return Semantics(
      selected: selected,
      button: true,
      label: destination.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(23),
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: selected ? 1.06 : 1,
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 21,
                    color: foreground,
                  ),
                ),
                if (showLabel) ...[
                  const SizedBox(height: 2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 64),
                    child: AnimatedDefaultTextStyle(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      style: theme.textTheme.labelSmall!.copyWith(
                        color: foreground,
                        fontSize: 10,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w400,
                      ),
                      child: Text(
                        destination.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ComposeReveal extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Offset offset;

  const ComposeReveal({
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, .04),
    Key? key,
  }) : super(key: key);

  @override
  State<ComposeReveal> createState() => _ComposeRevealState();
}

class _ComposeRevealState extends State<ComposeReveal>
    with SingleTickerProviderStateMixin {
  bool _started = false;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.value = 1;
    } else {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: widget.offset,
          end: Offset.zero,
        ).animate(_curve),
        child: widget.child,
      ),
    );
  }
}

class ComposePageSwitcher extends StatelessWidget {
  final Widget child;

  const ComposePageSwitcher({required this.child, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration:
          disableAnimations ? Duration.zero : const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) => Stack(
        fit: StackFit.expand,
        children: [...previousChildren, if (currentChild != null) currentChild],
      ),
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(.018, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

class ComposeSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final Gradient? gradient;
  final Color? color;
  final Border? border;

  const ComposeSurface({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.gradient,
    this.color,
    this.border,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? scheme.surfaceContainerLow.withValues(alpha: .82),
        gradient: gradient,
        borderRadius: borderRadius,
        border: border ??
            Border.all(color: scheme.outlineVariant.withValues(alpha: .55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha:
                  Theme.of(context).brightness == Brightness.dark ? .16 : .055,
            ),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class ComposePageTransitionsBuilder extends ZoomPageTransitionsBuilder {
  const ComposePageTransitionsBuilder({
    super.allowSnapshotting = true,
    super.allowEnterRouteSnapshotting = true,
    super.backgroundColor,
  });

  @override
  Duration get transitionDuration => const Duration(milliseconds: 160);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    return super.buildTransitions<T>(
      route,
      context,
      animation,
      secondaryAnimation,
      child,
    );
  }
}

const composePageTransitions = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: ComposePageTransitionsBuilder(),
    TargetPlatform.iOS: ComposePageTransitionsBuilder(),
    TargetPlatform.windows: ComposePageTransitionsBuilder(),
    TargetPlatform.macOS: ComposePageTransitionsBuilder(),
    TargetPlatform.linux: ComposePageTransitionsBuilder(),
  },
);
