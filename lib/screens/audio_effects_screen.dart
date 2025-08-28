import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/recorder_controller.dart';
import '../widgets/circular_eq_dial.dart';

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
  final ValueNotifier<List<double>> _gains = ValueNotifier(const [
    0.0,
    0.0,
    0.0,
  ]);
  final ValueNotifier<bool> _busy = ValueNotifier(false);

  Future<void> _apply(List<double> gains) async {
    final appliedGains = List<double>.unmodifiable(gains);
    _gains.value = appliedGains;
    _busy.value = true;
    try {
      await widget.controller.setPlaybackEqualizer(appliedGains);
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message ?? 'Audio effects are unavailable.'),
          ),
        );
      }
    } finally {
      if (mounted) _busy.value = false;
    }
  }

  @override
  void dispose() {
    _gains.dispose();
    _busy.dispose();
    super.dispose();
  }

  String _selectedPreset(List<double> gains) {
    for (final entry in _presets.entries) {
      var matches = true;
      for (var i = 0; i < 3; i++) {
        if ((entry.value[i] - gains[i]).abs() > 0.01) matches = false;
      }
      if (matches) return entry.key;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
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
          ValueListenableBuilder<List<double>>(
            valueListenable: _gains,
            builder: (context, gains, _) => ValueListenableBuilder<bool>(
              valueListenable: _busy,
              builder: (context, busy, _) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in _presets.entries)
                    ChoiceChip(
                      showCheckmark: false,
                      label: Text(entry.key, maxLines: 1, softWrap: false),
                      selected: _selectedPreset(gains) == entry.key,
                      onSelected: busy ? null : (_) => _apply(entry.value),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          ValueListenableBuilder<List<double>>(
            valueListenable: _gains,
            builder: (context, gains, _) => Row(
              children: [
                Expanded(
                  child: CircularEqDial(
                    label: 'Bass',
                    value: gains[0],
                    onChanged: (value) => _apply([value, gains[1], gains[2]]),
                  ),
                ),
                Expanded(
                  child: CircularEqDial(
                    label: 'Presence',
                    value: gains[1],
                    onChanged: (value) => _apply([gains[0], value, gains[2]]),
                  ),
                ),
                Expanded(
                  child: CircularEqDial(
                    label: 'Treble',
                    value: gains[2],
                    onChanged: (value) => _apply([gains[0], gains[1], value]),
                  ),
                ),
              ],
            ),
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
                  ValueListenableBuilder<bool>(
                    valueListenable: _busy,
                    builder: (context, busy, _) => busy
                        ? const Padding(
                            padding: EdgeInsets.only(left: 12),
                            child: SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
