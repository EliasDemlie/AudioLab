import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/recorder_controller.dart';

class AudioEffectsScreen extends StatefulWidget {
  const AudioEffectsScreen({super.key, required this.controller});

  final RecorderController controller;

  @override
  State<AudioEffectsScreen> createState() => _AudioEffectsScreenState();
}

class _AudioEffectsScreenState extends State<AudioEffectsScreen> {
  static const _presets = <String, List<double>>{
    'Flat': [0, 0, 0],
    'Voice': [-0.12, 0.22, 0.18],
    'Warm': [0.28, 0.08, -0.14],
    'Bright': [-0.12, 0.12, 0.32],
  };
  List<double> _gains = const [0, 0, 0];
  bool _busy = false;

  Future<void> _apply(List<double> gains) async {
    setState(() {
      _gains = List.unmodifiable(gains);
      _busy = true;
    });
    try {
      await widget.controller.setPlaybackEqualizer(_gains);
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Audio effects are unavailable.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _selectedPreset {
    for (final entry in _presets.entries) {
      var matches = true;
      for (var i = 0; i < 3; i++) {
        if ((entry.value[i] - _gains[i]).abs() > 0.01) matches = false;
      }
      if (matches) return entry.key;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = _selectedPreset;
    return Scaffold(
      appBar: AppBar(title: const Text('Effects')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Text(
            'Shape your sound',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Adjust playback EQ for a clearer voice preview.',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          Text(
            'PRESETS',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: colors.onSurfaceVariant, letterSpacing: 1.2),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in _presets.entries)
                ChoiceChip(
                  label: Text(entry.key),
                  selected: selected == entry.key,
                  onSelected: _busy ? null : (_) => _apply(entry.value),
                ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _GainSlider(
                  title: 'Bass',
                  subtitle: 'Low end',
                  value: _gains[0],
                  onChangeEnd: (value) => _apply([value, _gains[1], _gains[2]]),
                ),
              ),
              Expanded(
                child: _GainSlider(
                  title: 'Presence',
                  subtitle: 'Voice',
                  value: _gains[1],
                  onChangeEnd: (value) => _apply([_gains[0], value, _gains[2]]),
                ),
              ),
              Expanded(
                child: _GainSlider(
                  title: 'Treble',
                  subtitle: 'High end',
                  value: _gains[2],
                  onChangeEnd: (value) => _apply([_gains[0], _gains[1], value]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.headphones_rounded, color: colors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Effects preview during playback. Your original recording stays unchanged.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (_busy) ...[
                    const SizedBox(width: 12),
                    const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GainSlider extends StatefulWidget {
  const _GainSlider({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChangeEnd,
  });

  final String title;
  final String subtitle;
  final double value;
  final ValueChanged<double> onChangeEnd;

  @override
  State<_GainSlider> createState() => _GainSliderState();
}

class _GainSliderState extends State<_GainSlider> {
  late double _value = widget.value;

  @override
  void didUpdateWidget(covariant _GainSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _value = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = Theme.of(context).colorScheme;
    final amount = (_value * 12).round();
    final label = amount > 0 ? '+$amount dB' : '$amount dB';
    return Container(
      height: 236,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
        child: Column(
          children: [
            Container(
              width: 30,
              height: 7,
              decoration: BoxDecoration(
                color: colors.onSurface.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              widget.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            Expanded(
              child: Center(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SizedBox(
                    width: 132,
                    child: Slider(
                      value: _value.clamp(-1.0, 1.0),
                      min: -1,
                      max: 1,
                      onChanged: (value) => setState(() => _value = value),
                      onChangeEnd: widget.onChangeEnd,
                    ),
                  ),
                ),
              ),
            ),
            Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
