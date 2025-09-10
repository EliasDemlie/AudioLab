import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A bounded, scrolling waveform driven by the recorder's microphone peak meter.
class LiveWaveform extends StatefulWidget {
  const LiveWaveform({super.key, required this.level});

  final ValueListenable<double> level;

  @override
  State<LiveWaveform> createState() => _LiveWaveformState();
}

class _LiveWaveformState extends State<LiveWaveform> {
  static const _sampleCount = 38;
  final List<double> _samples = List<double>.filled(
    _sampleCount,
    0.025,
    growable: true,
  );

  @override
  void initState() {
    super.initState();
    widget.level.addListener(_onLevel);
  }

  @override
  void didUpdateWidget(covariant LiveWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.level != widget.level) {
      oldWidget.level.removeListener(_onLevel);
      widget.level.addListener(_onLevel);
    }
  }

  void _onLevel() {
    final previous = _samples.last;
    // Keep voice strength differences visible: louder peaks make taller bars.
    final current = widget.level.value == 0
        ? 0.0
        : math.pow(widget.level.value, 0.42).toDouble();
    final smoothing = current > previous ? 0.75 : 0.4;
    _samples
      ..removeAt(0)
      ..add(previous + (current - previous) * smoothing);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.level.removeListener(_onLevel);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 118,
    width: double.infinity,
    child: CustomPaint(
      painter: _WaveformPainter(
        samples: _samples,
        colors: [
          Theme.of(context).colorScheme.primary,
          const Color(0xFF36D9DF),
          const Color(0xFF8178FF),
        ],
      ),
    ),
  );
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.samples, required this.colors});

  final List<double> samples;
  final List<Color> colors;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.height / 2;
    final gap = 4.5;
    final barWidth = (size.width - gap * (samples.length - 1)) / samples.length;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < samples.length; i++) {
      final strength = samples[i].clamp(0.025, 1.0);
      final height = 4 + strength * (size.height * 0.65);
      final progress = i / (samples.length - 1);
      final color = progress < 0.5
          ? Color.lerp(colors[0], colors[1], progress * 2)!
          : Color.lerp(colors[1], colors[2], (progress - 0.5) * 2)!;
      paint.color = color.withValues(alpha: 0.88 + strength * 0.12);
      final x = i * (barWidth + gap) + barWidth / 2;
      canvas.drawLine(
        Offset(x, center - height / 2),
        Offset(x, center + height / 2),
        paint..strokeWidth = barWidth,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) => true;
}

class AudioLevelMeter extends StatelessWidget {
  const AudioLevelMeter({super.key, required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final clipping = level >= 0.88;
    final activeCount = (math.sqrt(level) * 22).ceil().clamp(0, 22);
    const palette = [
      Color(0xFF00D6CF),
      Color(0xFF24D98B),
      Color(0xFFF0D638),
      Color(0xFFFFA62B),
      Color(0xFF9A45F5),
    ];
    return Semantics(
      label: clipping
          ? 'Microphone level high, clipping risk'
          : 'Live microphone level',
      child: SizedBox(
        height: 27,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < 22; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 6,
                  height: 19,
                  decoration: BoxDecoration(
                    color: i < activeCount
                        ? (clipping && i > 18
                              ? Colors.redAccent
                              : palette[(i * palette.length) ~/ 22])
                        : palette[(i * palette.length) ~/ 22].withValues(
                            alpha: 0.18,
                          ),
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: i < activeCount
                        ? [
                            BoxShadow(
                              color: palette[(i * palette.length) ~/ 22]
                                  .withValues(alpha: 0.22),
                              blurRadius: 5,
                            ),
                          ]
                        : const [],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
