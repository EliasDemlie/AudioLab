import 'package:flutter/material.dart';

import 'circular_eq_dial.dart';

class EqualizerDials extends StatelessWidget {
  const EqualizerDials({
    super.key,
    required this.gains,
    required this.onChanged,
  });

  final List<double> gains;
  final ValueChanged<List<double>> onChanged;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = ((constraints.maxWidth - 16) / 3)
          .clamp(0.0, 144.0)
          .toDouble();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < 3; index++) ...[
            if (index > 0) const SizedBox(width: 8),
            Expanded(
              child: CircularEqDial(
                label: const ['Bass', 'Presence', 'Treble'][index],
                value: gains[index],
                size: size,
                onChanged: (value) {
                  final updated = List<double>.of(gains);
                  updated[index] = value;
                  onChanged(updated);
                },
              ),
            ),
          ],
        ],
      );
    },
  );
}
