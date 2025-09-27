import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'audio_preset_selector.dart';
import 'equalizer_dials.dart';

class AudioEqualizerPanel extends StatelessWidget {
  const AudioEqualizerPanel({
    super.key,
    required this.gains,
    required this.busy,
    required this.onChanged,
  });

  final ValueListenable<List<double>> gains;
  final ValueListenable<bool> busy;
  final ValueChanged<List<double>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialSpacing = MediaQuery.sizeOf(context).height < 640 ? 32.0 : 44.0;
    final panel = Column(
      children: [
        Row(
          children: [
            Text(
              'EQUALIZER',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
              ),
            ),
            const Spacer(),
            ValueListenableBuilder<bool>(
              valueListenable: busy,
              builder: (context, isBusy, _) => isBusy
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<List<double>>(
          valueListenable: gains,
          builder: (context, values, _) => ValueListenableBuilder<bool>(
            valueListenable: busy,
            builder: (context, isBusy, _) => AudioPresetSelector(
              gains: values,
              onSelected: isBusy ? null : onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        SizedBox(height: dialSpacing),
        ValueListenableBuilder<List<double>>(
          valueListenable: gains,
          builder: (context, values, _) =>
              EqualizerDials(gains: values, onChanged: onChanged),
        ),
      ],
    );
    if (theme.brightness == Brightness.dark) return panel;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.48),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: panel),
    );
  }
}
