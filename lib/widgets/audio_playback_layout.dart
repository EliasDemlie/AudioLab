import 'package:flutter/material.dart';

class AudioPlaybackLayout extends StatelessWidget {
  const AudioPlaybackLayout({
    super.key,
    required this.title,
    required this.waveformBuilder,
    required this.controls,
    required this.effects,
    required this.effectsVisible,
  });

  final String title;
  final Widget Function(double height) waveformBuilder;
  final Widget controls;
  final Widget effects;
  final bool effectsVisible;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).height < 640;

  static double controlSpacing(BuildContext context) =>
      isCompact(context) ? 8 : 12;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 580;
              final waveformHeight = (constraints.maxHeight * 0.24).clamp(
                64.0,
                180.0,
              );
              return Column(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: constraints.maxHeight * 0.65,
                    ),
                    child: SingleChildScrollView(
                      key: const ValueKey('audio-playback-main'),
                      primary: false,
                      padding: EdgeInsets.fromLTRB(
                        24,
                        compact ? 8 : 20,
                        24,
                        12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          waveformBuilder(waveformHeight),
                          SizedBox(height: compact ? 12 : 24),
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          SizedBox(height: compact ? 2 : 4),
                          controls,
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: Visibility(
                      visible: effectsVisible,
                      maintainState: true,
                      child: LayoutBuilder(
                        builder: (context, effectConstraints) {
                          final topPadding = compact ? 12.0 : 20.0;
                          final bottomPadding = compact ? 12.0 : 24.0;
                          return SingleChildScrollView(
                            key: const ValueKey('audio-playback-effects'),
                            primary: false,
                            padding: EdgeInsets.fromLTRB(
                              24,
                              topPadding,
                              24,
                              bottomPadding,
                            ),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight:
                                    (effectConstraints.maxHeight -
                                            topPadding -
                                            bottomPadding)
                                        .clamp(0.0, double.infinity),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.end,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [effects],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
