import 'dart:math' as math;

import 'package:flutter/material.dart';

class CircularEqDial extends StatefulWidget {
  const CircularEqDial({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.size = 112,
  }) : assert(size > 0);

  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final double size;

  @override
  State<CircularEqDial> createState() => _CircularEqDialState();
}

class _CircularEqDialState extends State<CircularEqDial> {
  late double _value = widget.value;
  bool _dragging = false;
  bool _rotating = false;
  double? _previousAngle;
  Offset? _dragOrigin;

  @override
  void didUpdateWidget(covariant CircularEqDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  String _labelFor(double value) {
    final gain = (value * 12).round();
    return gain > 0 ? '+$gain dB' : '$gain dB';
  }

  void _step(double amount) {
    setState(() => _value = (_value + amount).clamp(-1.0, 1.0).toDouble());
    widget.onChanged(_value);
  }

  void _startDrag(DragStartDetails details, double size) {
    final offset = details.localPosition - Offset(size / 2, size / 2);
    final origin =
        (_dragOrigin ?? details.localPosition) - Offset(size / 2, size / 2);
    setState(() {
      _dragging = true;
      _rotating = origin.distance >= size * 0.26;
      _previousAngle = math.atan2(offset.dy, offset.dx);
    });
  }

  void _updateDrag(DragUpdateDetails details, double size) {
    double change;
    if (_rotating) {
      final offset = details.localPosition - Offset(size / 2, size / 2);
      if (offset.distance < size * 0.14) {
        _previousAngle = null;
        return;
      }
      final angle = math.atan2(offset.dy, offset.dx);
      var delta = angle - (_previousAngle ?? angle);
      // Crossing the angle boundary should continue the same smooth turn.
      if (delta > math.pi) delta -= 2 * math.pi;
      if (delta < -math.pi) delta += 2 * math.pi;
      _previousAngle = angle;
      change = delta * 2 / (math.pi * 1.5);
    } else {
      change = -details.delta.dy / 100;
    }
    setState(() => _value = (_value + change).clamp(-1.0, 1.0).toDouble());
  }

  void _cancelDrag() {
    setState(() {
      _dragging = false;
      _value = widget.value;
      _dragOrigin = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final faceHighlight = Color.lerp(
      colors.surfaceContainerHigh,
      colors.onSurface,
      0.13,
    )!;
    final faceShadow = Color.lerp(
      colors.surfaceContainerHigh,
      Colors.black,
      0.3,
    )!;
    final lightFace = Color.lerp(
      colors.surface,
      colors.primaryContainer,
      0.55,
    )!;

    return Semantics(
      container: true,
      label: '${widget.label} gain',
      value: _labelFor(_value),
      increasedValue: _labelFor((_value + 0.1).clamp(-1.0, 1.0).toDouble()),
      decreasedValue: _labelFor((_value - 0.1).clamp(-1.0, 1.0).toDouble()),
      slider: true,
      onIncrease: () => _step(0.1),
      onDecrease: () => _step(-0.1),
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = math.min(widget.size, constraints.maxWidth);
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  key: ValueKey('eq-dial-${widget.label}'),
                  behavior: HitTestBehavior.opaque,
                  onPanDown: (details) => _dragOrigin = details.localPosition,
                  onPanStart: (details) => _startDrag(details, size),
                  onPanUpdate: (details) => _updateDrag(details, size),
                  onPanEnd: (_) {
                    if (!_dragging) return;
                    setState(() => _dragging = false);
                    _dragOrigin = null;
                    widget.onChanged(_value);
                  },
                  onPanCancel: _cancelDrag,
                  // An accepted pan also receives onPanEnd on pointer cancel.
                  // Reset before the recognizer handles that event to avoid
                  // committing an interrupted adjustment.
                  child: Listener(
                    onPointerCancel: (_) => _cancelDrag(),
                    child: SizedBox.square(
                      dimension: size,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _DialScalePainter(
                                value: _value,
                                accent: colors.primary,
                                track: colors.onSurface.withValues(alpha: 0.1),
                                tickColor: colors.onSurfaceVariant.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: size * 0.71,
                            height: size * 0.71,
                            padding: EdgeInsets.all(size * 0.026),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: dark ? null : colors.primaryContainer,
                              gradient: dark
                                  ? LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color.lerp(
                                          faceHighlight,
                                          Colors.white,
                                          0.25,
                                        )!,
                                        faceShadow,
                                        Color.lerp(
                                          faceShadow,
                                          Colors.black,
                                          0.35,
                                        )!,
                                      ],
                                      stops: const [0, 0.52, 1],
                                    )
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      (dark ? Colors.black : colors.onSurface)
                                          .withValues(alpha: dark ? 0.6 : 0.06),
                                  blurRadius: size * (dark ? 0.09 : 0.04),
                                  offset: Offset(
                                    0,
                                    size * (dark ? 0.055 : 0.025),
                                  ),
                                ),
                                if (dark)
                                  BoxShadow(
                                    color: Colors.white.withValues(alpha: 0.07),
                                    blurRadius: size * 0.035,
                                    offset: Offset(
                                      -size * 0.018,
                                      -size * 0.018,
                                    ),
                                  ),
                              ],
                            ),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: dark ? null : lightFace,
                                gradient: dark
                                    ? LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [faceHighlight, faceShadow],
                                      )
                                    : null,
                                border: Border.all(
                                  color: _dragging
                                      ? colors.primary.withValues(alpha: 0.7)
                                      : colors.onSurface.withValues(
                                          alpha: 0.08,
                                        ),
                                ),
                              ),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  Positioned.fill(
                                    child: Transform.rotate(
                                      angle: _value * math.pi * 0.75,
                                      child: Align(
                                        alignment: const Alignment(0, -0.78),
                                        child: Container(
                                          width: math.max(3, size * 0.034),
                                          height: size * 0.12,
                                          decoration: BoxDecoration(
                                            color: colors.primary,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                            boxShadow: dark
                                                ? [
                                                    BoxShadow(
                                                      color: colors.primary
                                                          .withValues(
                                                            alpha: 0.4,
                                                          ),
                                                      blurRadius: 7,
                                                    ),
                                                  ]
                                                : null,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: size * 0.06,
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        _labelFor(_value),
                                        style: theme.textTheme.labelLarge
                                            ?.copyWith(
                                              color: colors.onSurface,
                                              fontWeight: FontWeight.w700,
                                              fontFeatures: const [
                                                FontFeature.tabularFigures(),
                                              ],
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: size * 0.17,
                            child: Text('−', style: theme.textTheme.labelSmall),
                          ),
                          Positioned(
                            bottom: 0,
                            right: size * 0.17,
                            child: Text('+', style: theme.textTheme.labelSmall),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _DialScalePainter extends CustomPainter {
  const _DialScalePainter({
    required this.value,
    required this.accent,
    required this.track,
    required this.tickColor,
  });

  final double value;
  final Color accent;
  final Color track;
  final Color tickColor;

  static const _start = math.pi * 0.75;
  static const _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    final arc = Rect.fromCircle(center: center, radius: radius * 0.82);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, size.shortestSide * 0.026)
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(arc, _start, _sweep, false, stroke..color = track);
    final angle = _start + ((value + 1) / 2) * _sweep;
    canvas.drawArc(
      arc,
      -math.pi / 2,
      value * _sweep / 2,
      false,
      stroke..color = accent,
    );
    canvas.drawCircle(
      center + Offset(math.cos(angle), math.sin(angle)) * radius * 0.82,
      stroke.strokeWidth * 0.85,
      Paint()..color = accent,
    );

    final tick = Paint()
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var index = 0; index <= 24; index++) {
      final tickAngle = _start + index / 24 * _sweep;
      final direction = Offset(math.cos(tickAngle), math.sin(tickAngle));
      final major = index % 6 == 0;
      tick.color = index == 12 ? accent : tickColor;
      canvas.drawLine(
        center + direction * radius * (major ? 0.91 : 0.94),
        center + direction * radius * 0.99,
        tick,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DialScalePainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.accent != accent ||
      oldDelegate.track != track ||
      oldDelegate.tickColor != tickColor;
}
