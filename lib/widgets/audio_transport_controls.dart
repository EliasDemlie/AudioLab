import 'package:flutter/material.dart';

class AudioTransportControls extends StatelessWidget {
  const AudioTransportControls({
    super.key,
    required this.playing,
    required this.busy,
    required this.playTooltip,
    required this.leading,
    required this.trailing,
    required this.backTooltip,
    required this.forwardTooltip,
    required this.backIcon,
    required this.forwardIcon,
    this.onToggle,
    this.onBack,
    this.onForward,
  });

  final bool playing;
  final bool busy;
  final String playTooltip;
  final Widget leading;
  final Widget trailing;
  final String backTooltip;
  final String forwardTooltip;
  final IconData backIcon;
  final IconData forwardIcon;
  final VoidCallback? onToggle;
  final VoidCallback? onBack;
  final VoidCallback? onForward;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Row(
      children: [
        Expanded(
          child: Align(alignment: Alignment.centerLeft, child: leading),
        ),
        _SkipButton(tooltip: backTooltip, icon: backIcon, onPressed: onBack),
        const SizedBox(width: 12),
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: colors.primary.withValues(alpha: playing ? 0.36 : 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: playing ? 0.2 : 0.1),
                blurRadius: 30,
                spreadRadius: -2,
              ),
            ],
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dark ? null : colors.primary,
              gradient: dark
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colors.primary,
                        Color.lerp(colors.primary, colors.tertiary, 0.3)!,
                      ],
                    )
                  : null,
            ),
            child: SizedBox.square(
              dimension: 56,
              child: IconButton(
                tooltip: playTooltip,
                onPressed: onToggle,
                style: IconButton.styleFrom(
                  shape: const CircleBorder(),
                  foregroundColor: colors.onPrimary,
                  disabledForegroundColor: colors.onPrimary,
                ),
                icon: busy
                    ? SizedBox.square(
                        dimension: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colors.onPrimary,
                        ),
                      )
                    : AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          key: ValueKey(playing),
                          size: 32,
                        ),
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        _SkipButton(
          tooltip: forwardTooltip,
          icon: forwardIcon,
          onPressed: onForward,
        ),
        Expanded(
          child: Align(alignment: Alignment.centerRight, child: trailing),
        ),
      ],
    );
  }
}

class _SkipButton extends StatelessWidget {
  const _SkipButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 38,
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        style: IconButton.styleFrom(
          backgroundColor: colors.primary.withValues(alpha: 0.08),
          foregroundColor: colors.primary,
          disabledBackgroundColor: colors.primary.withValues(alpha: 0.04),
          disabledForegroundColor: colors.onSurface.withValues(alpha: 0.32),
          shape: const CircleBorder(),
          side: BorderSide(color: colors.primary.withValues(alpha: 0.18)),
        ),
      ),
    );
  }
}
