import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/recorder_controller.dart';
import '../widgets/audio_preset_selector.dart';
import '../widgets/equalizer_dials.dart';

class AudioEffectsScreen extends StatefulWidget {
  const AudioEffectsScreen({super.key, required this.controller});

  final RecorderController controller;

  @override
  State<AudioEffectsScreen> createState() => _AudioEffectsScreenState();
}

class _AudioEffectsScreenState extends State<AudioEffectsScreen> {
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
          ValueListenableBuilder<List<double>>(
            valueListenable: _gains,
            builder: (context, gains, _) => ValueListenableBuilder<bool>(
              valueListenable: _busy,
              builder: (context, busy, _) => AudioPresetSelector(
                gains: gains,
                onSelected: busy ? null : _apply,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ValueListenableBuilder<List<double>>(
            valueListenable: _gains,
            builder: (context, gains, _) =>
                EqualizerDials(gains: gains, onChanged: _apply),
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
