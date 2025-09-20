import 'package:flutter/material.dart';

class AudioPlaybackLayout extends StatelessWidget {
  const AudioPlaybackLayout({
    super.key,
    required this.title,
    required this.waveformBuilder,
    required this.controls,
    required this.effectButton,
    this.effects,
  });

  final String title;
  final Widget Function(double height) waveformBuilder;
  final Widget controls;
  final Widget effectButton;
  final Widget? effects;

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
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxHeight < 520;
                    final topPadding = compact ? 8.0 : 20.0;
                    final bottomPadding = compact ? 12.0 : 20.0;
                    final contentHeight =
                        (constraints.maxHeight - topPadding - bottomPadding)
                            .clamp(0.0, double.infinity);
                    final waveformHeight =
                        (contentHeight * (effects == null ? 0.52 : 0.22)).clamp(
                          64.0,
                          effects == null ? 320.0 : 160.0,
                        );

                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        24,
                        topPadding,
                        24,
                        bottomPadding,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: contentHeight),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            waveformBuilder(waveformHeight),
                            Padding(
                              padding: EdgeInsets.only(top: compact ? 12 : 24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  SizedBox(height: compact ? 2 : 4),
                                  controls,
                                ],
                              ),
                            ),
                            if (effects != null)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: compact ? 20 : 28,
                                ),
                                child: effects,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: effectButton,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
