import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'main_navigation.dart';

void main() {
  runApp(const VoiceRecApp());
}

class VoiceRecApp extends StatefulWidget {
  const VoiceRecApp({super.key});

  @override
  State<VoiceRecApp> createState() => _VoiceRecAppState();
}

class _VoiceRecAppState extends State<VoiceRecApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _toggleTheme() {
    final dark = switch (_themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };
    setState(() => _themeMode = dark ? ThemeMode.light : ThemeMode.dark);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Recorder',
      debugShowCheckedModeBanner: false,
      theme: VoiceRecTheme.light,
      darkTheme: VoiceRecTheme.dark,
      themeMode: _themeMode,
      builder: (context, child) => VoiceRecBackdrop(child: child!),
      home: MainNavigation(onToggleTheme: _toggleTheme),
    );
  }
}
