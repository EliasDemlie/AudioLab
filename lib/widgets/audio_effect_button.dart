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
