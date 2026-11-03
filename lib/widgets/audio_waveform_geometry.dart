import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Shared bar spacing and amplitude scaling for playback and trimming.
class AudioWaveformGeometry {
  AudioWaveformGeometry(List<double> peaks, this.size) {
    if (peaks.isEmpty) {
      bars = const [];
      return;
    }
    final width = math.max(1.0, size.width - inset * 2);
    final count = math.min(31, math.max(1, (width / 8).floor()));
    final barWidth = math.min(4.0, width);
    final step = count > 1 ? (width - barWidth) / (count - 1) : 0.0;
    bars = List.generate(count, (index) {
      final from = index * peaks.length ~/ count;
      final to = math.max(from + 1, (index + 1) * peaks.length ~/ count);
      var peak = 0.0;
      for (var sample = from; sample < to; sample++) {
        if (peaks[sample].isFinite) {
          peak = math.max(peak, peaks[sample].clamp(0.0, 1.0));
        }
      }
      final height = (5 + math.pow(peak, 0.65) * 78) * size.height / 124;
      return Rect.fromLTWH(
        inset + (count == 1 ? (width - barWidth) / 2 : index * step),
        (size.height - height) / 2,
        barWidth,
        height,
      );
    }, growable: false);
  }

  static const inset = 12.0;
  static const idleOpacity = 0.62;

  final Size size;
  late final List<Rect> bars;
}
