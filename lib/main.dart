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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF20D4CF),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF20D4CF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF061322),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF061322),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF0B1D30),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      themeMode: ThemeMode.dark,
      home: const RecorderScreen(),
    );
  }
}
