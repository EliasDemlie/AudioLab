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
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 28),
          Text(
            'PRESETS',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
              letterSpacing: 1.2,
            ),
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
          const SizedBox(height: 28),
          _GainSlider(
            title: 'Bass',
            subtitle: 'Low frequencies',
            value: _gains[0],
            onChanged: (value) =>
                setState(() => _gains = [value, _gains[1], _gains[2]]),
            onChangeEnd: (_) => _apply(_gains),
          ),
          const SizedBox(height: 20),
          _GainSlider(
            title: 'Presence',
            subtitle: 'Voice clarity',
            value: _gains[1],
            onChanged: (value) =>
                setState(() => _gains = [_gains[0], value, _gains[2]]),
            onChangeEnd: (_) => _apply(_gains),
          ),
          const SizedBox(height: 20),
          _GainSlider(
            title: 'Treble',
            subtitle: 'High frequencies',
            value: _gains[2],
            onChanged: (value) =>
                setState(() => _gains = [_gains[0], _gains[1], value]),
            onChangeEnd: (_) => _apply(_gains),
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

class _GainSlider extends StatelessWidget {
  const _GainSlider({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final String title;
  final String subtitle;
  final double value;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final amount = (value * 12).round();
    final label = amount > 0 ? '+$amount dB' : '$amount dB';
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(label, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
        Slider(
          value: value.clamp(-1.0, 1.0),
          min: -1,
          max: 1,
          onChanged: onChanged,
          onChangeEnd: onChangeEnd,
        ),
      ],
    );
  }
}
