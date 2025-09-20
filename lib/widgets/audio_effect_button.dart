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
      width: double.infinity,
      child: Semantics(
        toggled: visible,
        child: Tooltip(
          message: visible ? 'Hide effects' : 'Show effects',
          child: TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 52),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              backgroundColor: visible
                  ? colors.primary.withValues(alpha: 0.12)
                  : colors.primary.withValues(alpha: 0.05),
              shape: const StadiumBorder(),
              side: BorderSide(
                color: colors.primary.withValues(alpha: visible ? 0.3 : 0.12),
              ),
            ),
            child: const Text('Effect', maxLines: 1, softWrap: false),
          ),
        ),
      ),
    );
  }
}
