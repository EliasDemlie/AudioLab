import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// A recording's amplitude envelope with crop handles and a playback cursor.
class AudioCropWaveform extends StatefulWidget {
  const AudioCropWaveform({
    super.key,
    required this.peaks,
    required this.selection,
    required this.position,
    required this.onSelectionChanged,
    this.positionListenable,
    required this.onSeek,
    this.minimumSelection = 0,
    this.enabled = true,
  });

  final List<double> peaks;
  final RangeValues selection;
  final double position;

  /// Updates only the playback cursor's paint layer, without rebuilding handles.
  final ValueListenable<double>? positionListenable;
  final ValueChanged<RangeValues> onSelectionChanged;
  final ValueChanged<double> onSeek;
  final double minimumSelection;
  final bool enabled;

  @override
  State<AudioCropWaveform> createState() => _AudioCropWaveformState();
}

class _AudioCropWaveformState extends State<AudioCropWaveform> {
  static const _inset = 12.0;
  RangeValues? _dragSelection;
  bool? _draggingStart;
  double _dragDistance = 0;
  List<double>? _geometryPeaks;
  _WaveformGeometry? _geometry;

  _WaveformGeometry _geometryFor(Size size) {
    if (!identical(_geometryPeaks, widget.peaks) || _geometry?.size != size) {
      _geometryPeaks = widget.peaks;
      _geometry = _WaveformGeometry(widget.peaks, size);
    }
    return _geometry!;
  }

  void _changeHandle(bool start, double value, RangeValues selection) {
    final minimum = widget.minimumSelection.clamp(0.0, 1.0);
    widget.onSelectionChanged(
      start
          ? RangeValues(
              value.clamp(0.0, selection.end - minimum),
              selection.end,
            )
          : RangeValues(
              selection.start,
              value.clamp(selection.start + minimum, 1.0),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = widget.enabled && widget.peaks.isNotEmpty;
    return SizedBox(
      height: 112,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final trackWidth = math.max(1.0, constraints.maxWidth - _inset * 2);
          final startX = _inset + widget.selection.start * trackWidth;
          final endX = _inset + widget.selection.end * trackWidth;
          double fraction(double x) =>
              ((x - _inset) / trackWidth).clamp(0.0, 1.0);

          Widget handleSemantics(bool start, double x) {
            final value = start ? widget.selection.start : widget.selection.end;
            final step = math.max(0.01, widget.minimumSelection / 10);
            return Positioned(
              left: (x - _inset).clamp(0.0, constraints.maxWidth - 44),
              top: 0,
              bottom: 0,
              width: 44,
              child: Semantics(
                key: ValueKey(start ? 'crop-start-handle' : 'crop-end-handle'),
                container: true,
                label: start ? 'Crop start' : 'Crop end',
                value: '${(value * 100).round()}%',
                slider: true,
                enabled: enabled,
                increasedValue:
                    '${((value + step).clamp(0.0, 1.0) * 100).round()}%',
                decreasedValue:
                    '${((value - step).clamp(0.0, 1.0) * 100).round()}%',
                onIncrease: enabled
                    ? () => _changeHandle(start, value + step, widget.selection)
                    : null,
                onDecrease: enabled
                    ? () => _changeHandle(start, value - step, widget.selection)
                    : null,
                child: const ColoredBox(color: Colors.transparent),
              ),
            );
          }

          return Semantics(
            label: 'Audio waveform',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              dragStartBehavior: DragStartBehavior.down,
              onTapUp: enabled
                  ? (details) =>
                        widget.onSeek(fraction(details.localPosition.dx))
                  : null,
              onHorizontalDragStart: enabled
                  ? (details) {
                      final x = details.localPosition.dx;
                      final startDistance = (x - startX).abs();
                      final endDistance = (x - endX).abs();
                      _dragSelection = widget.selection;
                      _dragDistance = 0;
                      _draggingStart =
                          math.min(startDistance, endDistance) <= 22
                          ? startDistance <= endDistance
                          : null;
                      if (_draggingStart == null) widget.onSeek(fraction(x));
                    }
                  : null,
              onHorizontalDragUpdate: enabled
                  ? (details) {
                      final draggingStart = _draggingStart;
                      final initial = _dragSelection;
                      if (draggingStart == null || initial == null) {
                        widget.onSeek(fraction(details.localPosition.dx));
                        return;
                      }
                      _dragDistance += details.delta.dx;
                      _changeHandle(
                        draggingStart,
                        (draggingStart ? initial.start : initial.end) +
                            _dragDistance / trackWidth,
                        initial,
                      );
                    }
                  : null,
              onHorizontalDragEnd: (_) {
                _dragSelection = null;
                _draggingStart = null;
              },
              onHorizontalDragCancel: () {
                _dragSelection = null;
                _draggingStart = null;
              },
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        key: const ValueKey('crop-waveform-envelope'),
                        painter: _CropWaveformPainter(
                          geometry: _geometryFor(
                            Size(constraints.maxWidth, constraints.maxHeight),
                          ),
                          selection: widget.selection,
                          primary: colors.primary,
                          foreground: colors.onSurface,
                          enabled: enabled,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          key: const ValueKey('crop-waveform-cursor'),
                          painter: _PlaybackCursorPainter(
                            position: widget.position,
                            positionListenable: widget.positionListenable,
                            color: colors.onSurface,
                            visible: widget.peaks.isNotEmpty,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.peaks.isEmpty)
                    Center(
                      child: Text(
                        'Waveform unavailable',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ),
                  handleSemantics(true, startX),
                  handleSemantics(false, endX),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CropWaveformPainter extends CustomPainter {
  const _CropWaveformPainter({
    required this.geometry,
    required this.selection,
    required this.primary,
    required this.foreground,
    required this.enabled,
  });

  final _WaveformGeometry geometry;
  final RangeValues selection;
  final Color primary;
  final Color foreground;
  final bool enabled;

  @override
  void paint(Canvas canvas, Size size) {
    const inset = 12.0;
    final width = math.max(1.0, size.width - inset * 2);
    final area = Rect.fromLTWH(inset, 12, width, size.height - 24);
    final startX = area.left + selection.start * area.width;
    final endX = area.left + selection.end * area.width;
    final paint = Paint()..strokeCap = StrokeCap.round;
    paint.strokeCap = StrokeCap.round;
    for (final bar in geometry.bars) {
      final x = bar.x;
      final height = bar.height;
      final included = x >= startX && x <= endX;
      paint
        ..strokeWidth = geometry.strokeWidth
        ..color = included
            ? primary.withValues(alpha: enabled ? 0.95 : 0.4)
            : foreground.withValues(alpha: enabled ? 0.2 : 0.1);
      canvas.drawLine(
        Offset(x, area.center.dy - height / 2),
        Offset(x, area.center.dy + height / 2),
        paint,
      );
    }

    if (geometry.bars.isEmpty) return;
    paint
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = 2
      ..color = primary.withValues(alpha: enabled ? 0.95 : 0.35);
    for (final x in [startX, endX]) {
      canvas.drawLine(Offset(x, area.top), Offset(x, area.bottom), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropWaveformPainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.selection != selection ||
      oldDelegate.primary != primary ||
      oldDelegate.foreground != foreground ||
      oldDelegate.enabled != enabled;
}

/// The sampled bars depend on the audio and viewport, not the crop or playhead.
class _WaveformGeometry {
  _WaveformGeometry(List<double> peaks, this.size) {
    final width = math.max(1.0, size.width - 24);
    final count = math.min(peaks.length, math.max(1, (width / 4).floor()));
    final step = width / math.max(1, count);
    strokeWidth = math.min(3.0, step * 0.58);
    bars = List.generate(count, (i) {
      final from = i * peaks.length ~/ count;
      final to = math.max(from + 1, (i + 1) * peaks.length ~/ count);
      var peak = 0.0;
      for (var j = from; j < to; j++) {
        if (peaks[j].isFinite) peak = math.max(peak, peaks[j].clamp(0.0, 1.0));
      }
      return _WaveformBar(
        x: 12 + (i + 0.5) * step,
        height: math.max(2.0, math.pow(peak, 0.65) * (size.height - 62)),
      );
    }, growable: false);
  }

  final Size size;
  late final List<_WaveformBar> bars;
  late final double strokeWidth;
}

class _WaveformBar {
  const _WaveformBar({required this.x, required this.height});

  final double x;
  final double height;
}

class _PlaybackCursorPainter extends CustomPainter {
  _PlaybackCursorPainter({
    required this.position,
    required this.positionListenable,
    required this.color,
    required this.visible,
  }) : super(repaint: positionListenable);

  final double position;
  final ValueListenable<double>? positionListenable;
  final Color color;
  final bool visible;

  @override
  void paint(Canvas canvas, Size size) {
    if (!visible) return;
    final current = positionListenable?.value ?? position;
    final fraction = current.isFinite ? current.clamp(0.0, 1.0) : 0.0;
    final cursor = 12 + fraction * math.max(1.0, size.width - 24);
    final paint = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(cursor, 12),
      Offset(cursor, size.height - 12),
      paint,
    );
    canvas.drawCircle(Offset(cursor, 15), 4, paint);
  }

  @override
  bool shouldRepaint(covariant _PlaybackCursorPainter oldDelegate) =>
      oldDelegate.position != position ||
      oldDelegate.positionListenable != positionListenable ||
      oldDelegate.color != color ||
      oldDelegate.visible != visible;
}
