import 'package:flutter/material.dart';

class AudioPlaybackLayout extends StatelessWidget {
  const AudioPlaybackLayout({
    super.key,
    required this.title,
    required this.waveformBuilder,
    required this.controls,
    this.effects,
  });

  final String title;
  final Widget Function(double height) waveformBuilder;
  final Widget controls;
  final Widget? effects;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).height < 640;

  static double controlSpacing(BuildContext context) =>
      isCompact(context) ? 8 : 12;

  @override
  Widget build(BuildContext context) {
    final compact = isCompact(context);
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              compact ? 8 : 10,
              24,
              compact ? 12 : 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                waveformBuilder(compact ? 64 : 124),
                SizedBox(height: compact ? 8 : 14),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: compact ? 2 : 4),
                controls,
                if (effects != null) ...[
                  SizedBox(height: controlSpacing(context)),
                  effects!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
