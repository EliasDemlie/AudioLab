import 'package:flutter/material.dart';

import 'screens/recorder_screen.dart';

void main() {
  runApp(const VoiceRecApp());
}

class VoiceRecApp extends StatelessWidget {
  const VoiceRecApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Recorder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: const RecorderScreen(),
    );
  }
}
