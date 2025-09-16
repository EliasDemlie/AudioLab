import 'package:flutter/material.dart';

class CircularEqDial extends StatefulWidget {
  const CircularEqDial({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  State<CircularEqDial> createState() => _CircularEqDialState();
}

class _CircularEqDialState extends State<CircularEqDial> {
  late double _value = widget.value;
  bool _dragging = false;

  @override
  void didUpdateWidget(covariant CircularEqDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging && oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  String get _gainLabel {
    return _labelFor(_value);
  }

  String _labelFor(double value) {
    final gain = (value * 12).round();
    return gain > 0 ? '+$gain dB' : '$gain dB';
  }

  void _step(double amount) {
    widget.onChanged((widget.value + amount).clamp(-1.0, 1.0).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '${widget.label} gain',
      value: _gainLabel,
      increasedValue: _labelFor((_value + 0.1).clamp(-1.0, 1.0).toDouble()),
      decreasedValue: _labelFor((_value - 0.1).clamp(-1.0, 1.0).toDouble()),
      slider: true,
      onIncrease: () => _step(0.1),
      onDecrease: () => _step(-0.1),
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onPanStart: (_) => _dragging = true,
              onPanUpdate: (details) => setState(
                () => _value = (_value - details.delta.dy / 100)
                    .clamp(-1.0, 1.0)
                    .toDouble(),
              ),
              onPanEnd: (_) {
                _dragging = false;
                widget.onChanged(_value);
              },
              onPanCancel: () => setState(() {
                _dragging = false;
                _value = widget.value;
              }),
              child: SizedBox.square(
                dimension: 68,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                      value: (_value + 1) / 2,
                      strokeWidth: 5,
                      backgroundColor: colors.onSurface.withValues(alpha: 0.1),
                      valueColor: AlwaysStoppedAnimation(colors.primary),
                    ),
                    Text(
                      _gainLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
