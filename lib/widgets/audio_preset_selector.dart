import 'package:flutter/material.dart';

import '../utils/audio_effect_presets.dart';

class AudioPresetSelector extends StatelessWidget {
  const AudioPresetSelector({
    super.key,
    required this.gains,
    required this.onSelected,
    this.materialTapTargetSize,
  });

  final List<double> gains;
  final ValueChanged<List<double>>? onSelected;
  final MaterialTapTargetSize? materialTapTargetSize;

  @override
  Widget build(BuildContext context) => Row(
    spacing: 6,
    children: [
      for (final preset in audioEffectPresets.entries)
        Expanded(
          child: ChoiceChip(
            showCheckmark: false,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            labelPadding: EdgeInsets.zero,
            labelStyle: const TextStyle(fontSize: 12),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(preset.key, maxLines: 1, softWrap: false),
            ),
            materialTapTargetSize: materialTapTargetSize,
            selected: audioEffectPresetFor(gains) == preset.key,
            onSelected: onSelected == null
                ? null
                : (_) => onSelected!(preset.value),
          ),
        ),
    ],
  );
}
