import 'package:flutter/material.dart';

import '../utils/audio_effect_presets.dart';

class AudioPresetSelector extends StatelessWidget {
  const AudioPresetSelector({
    super.key,
    required this.gains,
    required this.onSelected,
    this.alignment = MainAxisAlignment.start,
    this.materialTapTargetSize,
  });

  final List<double> gains;
  final ValueChanged<List<double>>? onSelected;
  final MainAxisAlignment alignment;
  final MaterialTapTargetSize? materialTapTargetSize;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: constraints.maxWidth),
        child: Row(
          mainAxisAlignment: alignment,
          spacing: 8,
          children: [
            for (final preset in audioEffectPresets.entries)
              ChoiceChip(
                showCheckmark: false,
                label: Text(preset.key, maxLines: 1, softWrap: false),
                materialTapTargetSize: materialTapTargetSize,
                selected: audioEffectPresetFor(gains) == preset.key,
                onSelected: onSelected == null
                    ? null
                    : (_) => onSelected!(preset.value),
              ),
          ],
        ),
      ),
    ),
  );
}
