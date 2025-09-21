import 'package:flutter/material.dart';

class AudioEffectButton extends StatelessWidget {
  const AudioEffectButton({
    super.key,
    required this.visible,
    required this.onPressed,
  });

  final bool visible;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: 64,
      child: Semantics(
        toggled: visible,
        child: Tooltip(
          message: visible ? 'Hide effects' : 'Show effects',
          child: TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: visible
                  ? colors.primary.withValues(alpha: 0.12)
                  : colors.primary.withValues(alpha: 0.05),
              shape: const StadiumBorder(),
              side: BorderSide(
                color: colors.primary.withValues(alpha: visible ? 0.3 : 0.12),
              ),
            ),
            child: const FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Effect', maxLines: 1, softWrap: false),
            ),
          ),
        ),
      ),
    );
  }
}
