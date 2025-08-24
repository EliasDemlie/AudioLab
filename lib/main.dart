import 'package:flutter/material.dart';

import 'main_navigation.dart';

const _voiceTextTheme = TextTheme(
  displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
  headlineMedium: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
  headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
  titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
  titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
  bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400),
  bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400),
  bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
  labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
);

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
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF20D4CF),
          brightness: Brightness.light,
        ),
        textTheme: _voiceTextTheme,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF20D4CF),
          brightness: Brightness.dark,
        ),
        textTheme: _voiceTextTheme,
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
      home: const MainNavigation(),
    );
  }
}
