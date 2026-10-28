import 'package:flutter/material.dart';

class AppBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String? tooltip;

  const AppBackButton({
    super.key,
    this.onPressed,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    if (ModalRoute.of(context)?.canPop != true) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: IconButton(
          tooltip:
              tooltip ?? MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: onPressed ?? () => Navigator.maybePop(context),
          style: IconButton.styleFrom(
            fixedSize: const Size(38, 38),
            minimumSize: const Size(38, 38),
            maximumSize: const Size(38, 38),
            padding: EdgeInsets.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor:
                scheme.surfaceContainerHighest.withValues(alpha: .72),
            foregroundColor: scheme.onSurface,
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: .35),
            ),
            shape: const CircleBorder(),
          ),
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
        ),
      ),
    );
  }
}
